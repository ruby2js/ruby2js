defmodule JuntosBeam do
  @moduledoc """
  Juntos on BEAM - runs a Ruby2JS-transpiled Rails app inside QuickBEAM.
  """

  use GenServer

  require Logger

  @app_script "app.js"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Dispatch a Plug.Conn-style request to the JS application.
  Returns {status, headers, body}.
  """
  def dispatch(method, path, headers, body \\ nil) do
    GenServer.call(__MODULE__, {:dispatch, method, path, headers, body}, 30_000)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    port = Keyword.get(opts, :port, String.to_integer(System.get_env("PORT", "3000")))
    database = Keyword.get(opts, :database, "storage/development.sqlite3")

    # Ensure database directory exists
    database |> Path.dirname() |> File.mkdir_p!()

    # Start QuickBEAM runtime with the bundled app
    {:ok, rt} = QuickBEAM.start()

    # Stub browser globals that server-side code may reference
    QuickBEAM.eval(rt, "globalThis.window = globalThis;")

    # Load the application script
    {:ok, _} = QuickBEAM.eval(rt, File.read!(@app_script))

    # Load sqlite-napi addon (makes `sqlite` global available in JS)
    # Determine platform-specific .node file
    {os, _} = :os.type()
    arch = :erlang.system_info(:system_architecture) |> to_string()
    is_arm = String.contains?(arch, "aarch64") or String.contains?(arch, "arm64")
    node_file = case {os, is_arm} do
      {:darwin, true} -> "sqlite-napi.darwin-arm64.node"
      {:darwin, false} -> "sqlite-napi.darwin-x64.node"
      {:linux, true} -> "sqlite-napi.linux-arm64-gnu.node"
      {:linux, false} -> "sqlite-napi.linux-x64-gnu.node"
      _ -> "sqlite-napi.darwin-arm64.node"
    end
    addon_path = Path.join(["node_modules", "sqlite-napi", node_file])

    case QuickBEAM.load_addon(rt, addon_path, as: "sqlite") do
      {:ok, _} -> Logger.info("sqlite-napi addon loaded: #{node_file}")
      {:error, reason} -> Logger.warning("sqlite-napi not loaded: #{inspect(reason)}")
    end

    # Initialize the database
    {:ok, _} = QuickBEAM.eval(rt, """
      await initDatabase({ database: '#{database}' });
    """)

    Logger.info("Juntos BEAM app ready (database: #{database}, port: #{port})")

    {:ok, %{runtime: rt, port: port}}
  end

  @impl true
  def handle_call({:dispatch, method, path, headers, body}, _from, state) do
    # Build a Web Request object in JS and dispatch it
    # Convert headers map to array of [key, value] pairs (QuickBEAM's Headers format)
    headers_pairs = headers |> Enum.map(fn {k, v} -> [k, v] end) |> Jason.encode!()
    body_js = if body, do: ", body: #{Jason.encode!(body)}", else: ""

    js = """
      async function __dispatch() {
        try {
          const request = new Request('http://localhost#{path}', {
            method: '#{method}',
            headers: new Headers(#{headers_pairs})#{body_js}
          });
          const response = await Router.dispatch(request);
          const responseHeaders = {};
          const h = response.headers;
          if (h && typeof h.get === 'function') {
            for (const name of ['content-type', 'location', 'set-cookie', 'cache-control']) {
              const v = h.get(name);
              if (v) responseHeaders[name] = v;
            }
          }
          // Read body — try text() first, fall back to decoding raw body
          let body = '';
          try {
            body = await response.text();
          } catch(e) {
            const raw = response._body || response.body;
            if (raw instanceof Uint8Array) {
              body = new TextDecoder().decode(raw);
            } else if (typeof raw === 'string') {
              body = raw;
            } else {
              body = String(raw || '');
            }
          }
          return JSON.stringify({
            status: response.status,
            headers: responseHeaders,
            body: body
          });
        } catch(e) {
          return JSON.stringify({
            status: 500,
            headers: {'content-type': 'text/plain'},
            body: e.name + ': ' + e.message + '\\n' + (e.stack || '')
          });
        }
      }
      await __dispatch()
    """

    case QuickBEAM.eval(state.runtime, js) do
      {:ok, result} when is_binary(result) ->
        case Jason.decode(result) do
          {:ok, %{"status" => status, "headers" => resp_headers, "body" => resp_body}} ->
            {:reply, {:ok, status, resp_headers, resp_body}, state}

          {:error, _} ->
            Logger.error("Failed to parse JS response: #{inspect(result)}")
            {:reply, {:ok, 500, %{}, "Internal Server Error"}, state}
        end

      {:ok, other} ->
        Logger.error("Unexpected JS result: #{inspect(other)}")
        {:reply, {:ok, 500, %{}, "Internal Server Error"}, state}

      {:error, reason} ->
        Logger.error("JS dispatch error: #{inspect(reason)}")
        {:reply, {:ok, 500, %{}, "Internal Server Error"}, state}
    end
  end
end
