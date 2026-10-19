defmodule HoloChatWeb.AssistantPresence do
  @moduledoc """
  Shows the assistant personas and cast characters in room presence: online
  while they are in the room and enabled, and typing while they generate a
  reply. Driven by the
  assistant's status events, so the core never has to know about web-layer
  presence.
  """

  use GenServer

  alias HoloChat.Assistant
  alias HoloChatWeb.Presence

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Assistant.subscribe()
    # Catch up with assistants that started before us.
    Assistant.broadcast(:assistant_status_request)
    {:ok, %{}}
  end

  # `tracked` maps {room, name} to the presence meta last tracked for it.
  @impl true
  def handle_info({:assistant_status, %{room: room, name: name, online: false}}, tracked) do
    if Map.has_key?(tracked, {room, name}), do: Presence.untrack_user(room, key(name))
    {:noreply, Map.delete(tracked, {room, name})}
  end

  def handle_info({:assistant_status, %{room: room, name: name} = status}, tracked) do
    meta = %{
      name: name,
      typing: status.typing,
      avatar_id: status.avatar_id,
      persona_id: status.persona_id,
      character_id: status[:character_id],
      assistant: true
    }

    cond do
      tracked[{room, name}] == meta -> :ok
      Map.has_key?(tracked, {room, name}) -> Presence.update_user(room, key(name), meta)
      true -> Presence.track_user(room, key(name), meta)
    end

    {:noreply, Map.put(tracked, {room, name}, meta)}
  end

  def handle_info(_other_event, tracked), do: {:noreply, tracked}

  defp key(name), do: "assistant:" <> String.downcase(name)
end
