defmodule HoloChatWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  Each connected chat view is tracked twice under the same key:

    * in its room's topic (`topic/1`), with `%{name: String.t() | nil, typing: boolean()}`,
      for the room's online list and typing indicator;
    * in the global rooms topic, with `%{room: String.t()}`, for per-room
      online counts in the room list.

  Subscribers receive `presence_diff` broadcasts for the topics they subscribed to.

  See the [`Phoenix.Presence`](https://phoenix.hexdocs.pm/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :holo_chat,
    pubsub_server: HoloChat.PubSub

  @rooms_topic "presence:rooms"

  def topic(room), do: "presence:" <> room

  def subscribe(room), do: Phoenix.PubSub.subscribe(HoloChat.PubSub, topic(room))
  def unsubscribe(room), do: Phoenix.PubSub.unsubscribe(HoloChat.PubSub, topic(room))

  def track_user(room, key, meta), do: track(self(), topic(room), key, meta)
  def update_user(room, key, meta), do: update(self(), topic(room), key, meta)
  def untrack_user(room, key), do: untrack(self(), topic(room), key)

  @doc """
  Returns `{key, meta}` for every view currently in `room`.
  """
  def list_users(room) do
    for {key, %{metas: [meta | _]}} <- list(topic(room)), do: {key, meta}
  end

  def subscribe_rooms, do: Phoenix.PubSub.subscribe(HoloChat.PubSub, @rooms_topic)

  @doc """
  Records that the view `key` is now in `room`, for the room counts.
  """
  def put_room(key, room) do
    case update(self(), @rooms_topic, key, %{room: room}) do
      {:error, :nopresence} -> track(self(), @rooms_topic, key, %{room: room})
      ok -> ok
    end
  end

  def rooms_topic?(topic), do: topic == @rooms_topic

  @doc """
  Returns `%{room => number of connected views}` for every occupied room.
  """
  def room_counts do
    for {_key, %{metas: [%{room: room} | _]}} <- list(@rooms_topic), reduce: %{} do
      counts -> Map.update(counts, room, 1, &(&1 + 1))
    end
  end
end
