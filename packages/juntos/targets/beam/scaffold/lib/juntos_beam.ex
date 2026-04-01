defmodule JuntosBeam do
  @moduledoc """
  Juntos on BEAM - runs a Ruby2JS-transpiled Rails app inside QuickBEAM.

  Uses a pool of QuickBEAM runtimes with round-robin dispatch for
  concurrent request handling. Each runtime has its own JS context
  and OS thread, providing true parallelism.
  """

  use GenServer

  require Logger

  @app_script "app.js"

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Dispatch an HTTP request to the JS application.
  Picks the next runtime from the pool via round-robin.
  Returns {:ok, status, headers, body}.
  """
  def dispatch(method, path, headers, body \\ nil) do
    rt = GenServer.call(__MODULE__, :checkout)

    # Convert headers map to array of [key, value] pairs (QuickBEAM's Headers format)
    headers_pairs = headers |> Enum.map(fn {k, v} -> [k, v] end) |> Jason.encode!()
    # body is passed via globalThis.__requestBody, not through Request constructor

    # Store raw body for parseBody to access (Request.text() not available in QuickBEAM)
    escaped_body = if body, do: Jason.encode!(body), else: "null"

    js = """
      async function __dispatch() {
        try {
          globalThis.__requestBody = #{escaped_body};
          const request = new Request('http://localhost#{path}', {
            method: '#{method}',
            headers: new Headers(#{headers_pairs})
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

    case QuickBEAM.eval(rt, js) do
      {:ok, result} when is_binary(result) ->
        case Jason.decode(result) do
          {:ok, %{"status" => status, "headers" => resp_headers, "body" => resp_body}} ->
            {:ok, status, resp_headers, resp_body}

          {:error, _} ->
            Logger.error("Failed to parse JS response: #{inspect(result)}")
            {:ok, 500, %{}, "Internal Server Error"}
        end

      {:ok, other} ->
        Logger.error("Unexpected JS result: #{inspect(other)}")
        {:ok, 500, %{}, "Internal Server Error"}

      {:error, reason} ->
        Logger.error("JS dispatch error: #{inspect(reason)}")
        {:ok, 500, %{}, "Internal Server Error"}
    end
  end

  # Server callbacks

  @impl true
  def init(opts) do
    adapter = Keyword.get(opts, :adapter, System.get_env("JUNTOS_DATABASE", "sqlite_napi"))
    database = Keyword.get(opts, :database, default_database(adapter))
    pool_size = Keyword.get(opts, :pool_size, max(4, System.schedulers_online()))

    # Ensure database directory exists for file-based databases
    if adapter in ["sqlite_napi", "sqlite-napi"] do
      database |> Path.dirname() |> File.mkdir_p!()
    end

    # Base handlers (broadcast)
    handlers = %{
      "__broadcast" => fn [channel, html] ->
        JuntosBeam.Cable.broadcast(channel, html)
      end
    }

    # Add database handlers for Postgrex adapter
    handlers =
      if adapter in ["postgrex", "pg", "postgres"] do
        Map.merge(handlers, JuntosBeam.Database.postgrex_handlers())
      else
        handlers
      end

    app_code = File.read!(@app_script)

    Logger.info(
      "Starting QuickBEAM pool: #{pool_size} runtimes " <>
      "(adapter: #{adapter}, database: #{database})"
    )

    # Start N runtimes, each with the app loaded
    runtimes =
      for _i <- 1..pool_size do
        {:ok, rt} = QuickBEAM.start(handlers: handlers)

        # Stub browser globals and patch Response constructor for string bodies
        # QuickBEAM's Response requires Uint8Array body; this wrapper auto-encodes strings
        QuickBEAM.eval(rt, """
          globalThis.window = globalThis;
          const _OrigResponse = globalThis.Response;
          globalThis.Response = class extends _OrigResponse {
            constructor(body, init = {}) {
              const encoded = typeof body === 'string' ? new TextEncoder().encode(body)
                : body instanceof Uint8Array ? body
                : body == null ? null
                : new TextEncoder().encode(String(body));
              const headers = init.headers instanceof Headers ? init.headers
                : new Headers(Object.entries(init.headers || {}));
              super(encoded, {
                status: init.status || 200,
                statusText: init.statusText || 'OK',
                headers: headers,
                url: init.url || ''
              });
            }
          };
        """)

        # Load the application
        {:ok, _} = QuickBEAM.eval(rt, app_code)

        # Load sqlite-napi addon for SQLite adapters
        if adapter in ["sqlite_napi", "sqlite-napi"] do
          load_sqlite_addon(rt)
        end

        # Initialize the database
        db_config = Jason.encode!(%{database: database})
        {:ok, _} = QuickBEAM.eval(rt, "await initDatabase(#{db_config});")

        rt
      end

    Logger.info("QuickBEAM pool ready (#{pool_size} runtimes)")

    {:ok, %{runtimes: List.to_tuple(runtimes), counter: 0, size: pool_size}}
  end

  @impl true
  def handle_call(:checkout, _from, state) do
    index = rem(state.counter, state.size)
    rt = elem(state.runtimes, index)
    {:reply, rt, %{state | counter: state.counter + 1}}
  end

  # Private

  defp default_database(adapter) when adapter in ["sqlite_napi", "sqlite-napi"],
    do: "storage/development.sqlite3"
  defp default_database(_adapter),
    do: System.get_env("DATABASE_URL", "postgres://localhost/juntos_dev")

  defp load_sqlite_addon(rt) do
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
  end
end
