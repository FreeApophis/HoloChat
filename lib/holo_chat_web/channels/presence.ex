defmodule HoloChatWeb.Presence do
  @moduledoc """
  Provides presence tracking to channels and processes.

  Each connected chat view is tracked in its room under a unique key,
  with `%{name: String.t() | nil, typing: boolean()}` as metadata.
  Subscribers to `topic/1` receive `presence_diff` broadcasts.

  See the [`Phoenix.Presence`](https://phoenix.hexdocs.pm/Phoenix.Presence.html)
  docs for more details.
  """
  use Phoenix.Presence,
    otp_app: :holo_chat,
    pubsub_server: HoloChat.PubSub

  def topic(room), do: "presence:" <> room

  def subscribe(room) do
    Phoenix.PubSub.subscribe(HoloChat.PubSub, topic(room))
  end

  def track_user(room, key, meta) do
    track(self(), topic(room), key, meta)
  end

  def update_user(room, key, meta) do
    update(self(), topic(room), key, meta)
  end

  @doc """
  Returns `{key, meta}` for every view currently in `room`.
  """
  def list_users(room) do
    for {key, %{metas: [meta | _]}} <- list(topic(room)), do: {key, meta}
  end
end
