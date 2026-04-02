defmodule JuntosBeam.Router do
  @moduledoc """
  Plug router that dispatches HTTP requests to the QuickBEAM JS runtime.
  Serves static assets and handles WebSocket upgrades for Turbo Streams.
  """

  use Plug.Router

  plug Plug.Static,
    at: "/",
    from: ".",
    only: ~w(assets app favicon.ico icon.png icon.svg robots.txt)

  plug :match
  plug :dispatch

  # WebSocket endpoint for Turbo Streams broadcasting
  get "/cable" do
    require Logger
    Logger.info("WebSocket upgrade request for /cable")
    conn
    |> WebSockAdapter.upgrade(JuntosBeam.CableSocket, [], timeout: 60_000)
    |> halt()
  end

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

    {:ok, status, resp_headers, resp_body} =
      JuntosBeam.dispatch(method, full_path, headers, body)

    conn =
      Enum.reduce(resp_headers, conn, fn {key, value}, acc ->
        Plug.Conn.put_resp_header(acc, key, value)
      end)

    Plug.Conn.send_resp(conn, status, resp_body)
  end
end
