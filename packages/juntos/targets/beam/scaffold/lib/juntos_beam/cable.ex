defmodule JuntosBeam.Cable do
  @moduledoc """
  WebSocket handler for Turbo Streams broadcasting.
  Implements Action Cable protocol for compatibility with @hotwired/turbo-rails.

  Manages subscriptions and broadcasts entirely in Elixir.
  JS only sends broadcast messages via Beam.callSync.
  """

  require Logger

  # Registry of channel -> set of subscriber pids
  # Uses :pg (process groups) for distributed broadcasting
  @pg_scope :juntos_cable

  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {:pg, :start_link, [@pg_scope]},
      type: :worker
    }
  end

  # Called by JS via Beam.callSync('__broadcast', channel, html)
  def broadcast(channel, html) do
    # Action Cable message format
    identifier = Jason.encode!(%{
      "channel" => "Turbo::StreamsChannel",
      "signed_stream_name" => Base.encode64(Jason.encode!(channel))
    })

    message = Jason.encode!(%{
      "identifier" => identifier,
      "message" => html
    })

    # Send to all subscribers of this channel across the cluster
    members = :pg.get_members(@pg_scope, channel)
    Logger.debug("Broadcasting to #{channel} (#{length(members)} subscribers)")

    for pid <- members do
      send(pid, {:broadcast, message})
    end

    :ok
  end

  # Subscribe the calling process to a channel
  def subscribe(channel) do
    :pg.join(@pg_scope, channel, self())
  end

  # Unsubscribe the calling process from a channel
  def unsubscribe(channel) do
    :pg.leave(@pg_scope, channel, self())
  end

  # Unsubscribe from all channels
  def unsubscribe_all do
    for group <- :pg.which_groups(@pg_scope),
        self() in :pg.get_members(@pg_scope, group) do
      :pg.leave(@pg_scope, group, self())
    end
  end
end

defmodule JuntosBeam.CableSocket do
  @moduledoc """
  WebSock handler for individual WebSocket connections.
  Implements the Action Cable protocol.
  """

  @behaviour WebSock

  require Logger

  @impl true
  def init(_opts) do
    # Send Action Cable welcome message
    welcome = Jason.encode!(%{"type" => "welcome"})

    # Start ping timer (Action Cable stale threshold is 6s)
    Process.send_after(self(), :ping, 3_000)

    {:push, {:text, welcome}, %{}}
  end

  @impl true
  def handle_in({text, [opcode: :text]}, state) do
    case Jason.decode(text) do
      {:ok, %{"command" => "subscribe", "identifier" => identifier}} ->
        handle_subscribe(identifier, state)

      {:ok, %{"command" => "unsubscribe", "identifier" => identifier}} ->
        handle_unsubscribe(identifier, state)

      {:ok, %{"type" => "ping"}} ->
        pong = Jason.encode!(%{"type" => "pong"})
        {:push, {:text, pong}, state}

      _ ->
        {:ok, state}
    end
  end

  @impl true
  def handle_info({:broadcast, message}, state) do
    {:push, {:text, message}, state}
  end

  def handle_info(:ping, state) do
    ping = Jason.encode!(%{"type" => "ping", "message" => System.system_time(:second)})
    Process.send_after(self(), :ping, 3_000)
    {:push, {:text, ping}, state}
  end

  @impl true
  def terminate(_reason, _state) do
    JuntosBeam.Cable.unsubscribe_all()
    :ok
  end

  # Private

  defp handle_subscribe(identifier, state) do
    case decode_stream_name(identifier) do
      {:ok, channel} ->
        JuntosBeam.Cable.subscribe(channel)
        Logger.debug("Subscribed to channel: #{channel}")

        confirm = Jason.encode!(%{
          "type" => "confirm_subscription",
          "identifier" => identifier
        })

        {:push, {:text, confirm}, state}

      :error ->
        {:ok, state}
    end
  end

  defp handle_unsubscribe(identifier, state) do
    case decode_stream_name(identifier) do
      {:ok, channel} ->
        JuntosBeam.Cable.unsubscribe(channel)
        Logger.debug("Unsubscribed from channel: #{channel}")
        {:ok, state}

      :error ->
        {:ok, state}
    end
  end

  # Decode Action Cable signed_stream_name
  # Format: base64(JSON.stringify(streamName)) + "--" + signature
  defp decode_stream_name(identifier) do
    with {:ok, parsed} <- Jason.decode(identifier),
         signed_name when is_binary(signed_name) <- parsed["signed_stream_name"],
         base64_part <- String.split(signed_name, "--") |> List.first(),
         {:ok, decoded} <- Base.decode64(base64_part),
         {:ok, channel} <- Jason.decode(decoded) do
      {:ok, channel}
    else
      _ -> :error
    end
  end
end
