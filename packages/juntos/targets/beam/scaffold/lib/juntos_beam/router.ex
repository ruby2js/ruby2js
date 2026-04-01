defmodule JuntosBeam.Router do
  @moduledoc """
  Plug router that dispatches HTTP requests to the QuickBEAM JS runtime.
  Serves static assets directly from the public/ directory.
  """

  use Plug.Router

  plug Plug.Static,
    at: "/",
    from: "public",
    only: ~w(assets app favicon.ico robots.txt)

  plug :match
  plug :dispatch

  # Catch-all: forward everything to the JS application
  match _ do
    method = conn.method
    path = conn.request_path
    query = if conn.query_string != "", do: "?#{conn.query_string}", else: ""
    full_path = path <> query

    # Collect headers as a map
    headers =
      conn.req_headers
      |> Enum.into(%{})

    # Read body if present
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    body = if body == "", do: nil, else: body

    case JuntosBeam.dispatch(method, full_path, headers, body) do
      {:ok, status, resp_headers, resp_body} ->
        conn =
          Enum.reduce(resp_headers, conn, fn {key, value}, acc ->
            Plug.Conn.put_resp_header(acc, key, value)
          end)

        Plug.Conn.send_resp(conn, status, resp_body)

      {:error, _reason} ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(500, "<h1>500 Internal Server Error</h1>")
    end
  end
end
