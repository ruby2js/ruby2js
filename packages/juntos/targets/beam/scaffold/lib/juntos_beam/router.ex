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
    # Echo the Action Cable subprotocol so the browser doesn't reject the connection
    conn = case Plug.Conn.get_req_header(conn, "sec-websocket-protocol") do
      [protocols | _] ->
        # Client requests "actioncable-v1-json, actioncable-unsupported"
        # Echo back the first supported one
        protocol = protocols |> String.split(",") |> List.first() |> String.trim()
        Plug.Conn.put_resp_header(conn, "sec-websocket-protocol", protocol)
      _ ->
        conn
    end

    WebSockAdapter.upgrade(conn, JuntosBeam.CableSocket, %{}, timeout: 60_000)
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
