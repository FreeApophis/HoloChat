defmodule HoloChatWeb.AssistantPresence do
  @moduledoc """
  Shows the AI assistant in room presence: online while enabled, and
  typing while it generates a reply. Driven by the assistant's status
  events, so the core never has to know about web-layer presence.
  """

  use GenServer

  alias HoloChat.Assistant
  alias HoloChatWeb.Presence

  @key "assistant"

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Assistant.subscribe()
    # Catch up with assistants that started before us.
    Assistant.broadcast(:assistant_status_request)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:assistant_status, %{room: room, online: false}}, tracked) do
    if Map.has_key?(tracked, room), do: Presence.untrack_user(room, @key)
    {:noreply, Map.delete(tracked, room)}
  end

  def handle_info({:assistant_status, %{room: room, name: name, typing: typing}}, tracked) do
    meta = %{name: name, typing: typing}

    cond do
      tracked[room] == meta -> :ok
      Map.has_key?(tracked, room) -> Presence.update_user(room, @key, meta)
      true -> Presence.track_user(room, @key, meta)
    end

    {:noreply, Map.put(tracked, room, meta)}
  end

  def handle_info(_other_event, tracked), do: {:noreply, tracked}
end
