defmodule HoloChat.Chat do
  @moduledoc """
  The Chat context: persisting messages and broadcasting them to
  everyone subscribed to a room.
  """

  use Boundary, deps: [HoloChat.Repo, HoloChat.Accounts], exports: [Message]

  import Ecto.Query, warn: false

  alias HoloChat.Accounts.{Scope, User}
  alias HoloChat.Chat.Message
  alias HoloChat.Repo

  @pubsub HoloChat.PubSub
  @rooms_topic "rooms"
  @room_format ~r/\A[a-z0-9][a-z0-9-]{0,31}\z/

  @doc """
  Returns true if `room` is a valid room name: lowercase letters,
  digits and dashes, up to 32 characters, not starting with a dash.
  """
  def valid_room?(room) when is_binary(room), do: Regex.match?(@room_format, room)
  def valid_room?(_), do: false

  @doc """
  Subscribes the calling process to new messages in `room`.

  Subscribers receive `{:new_message, %Message{}}`.
  """
  def subscribe(room) do
    Phoenix.PubSub.subscribe(@pubsub, topic(room))
  end

  @doc """
  Stops receiving new messages from `room`.
  """
  def unsubscribe(room) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(room))
  end

  @doc """
  Subscribes the calling process to activity in all rooms.

  Subscribers receive `{:room_activity, room, %DateTime{}}` for every new message.
  """
  def subscribe_rooms do
    Phoenix.PubSub.subscribe(@pubsub, @rooms_topic)
  end

  @doc """
  Returns up to `limit` rooms that have messages, most recently active first,
  as `%{name: room, last_message_at: datetime}` maps.
  """
  def list_active_rooms(limit \\ 20) do
    Message
    |> group_by([m], m.room)
    |> select([m], %{name: m.room, last_message_at: max(m.inserted_at)})
    # Ids break ties: clock resolution can give messages equal timestamps.
    |> order_by([m], desc: max(m.inserted_at), desc: max(m.id))
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns the most recent `limit` messages in `room`, oldest first.
  """
  def list_recent_messages(room, limit \\ 50) do
    {messages, _more?} = list_messages_page(room, nil, limit)
    messages
  end

  @doc """
  Returns up to `limit` messages in `room` older than the `before` message
  (or the latest ones when `before` is nil), oldest first, together with
  whether even older messages exist.

  Messages are ordered by `(inserted_at, id)`, so paging is exact even when
  timestamps are equal.
  """
  def list_messages_page(room, before, limit) do
    messages =
      Message
      |> where(room: ^room)
      |> older_than(before)
      |> order_by(desc: :inserted_at, desc: :id)
      |> limit(^(limit + 1))
      |> Repo.all()

    {messages |> Enum.take(limit) |> Enum.reverse(), length(messages) > limit}
  end

  defp older_than(query, nil), do: query

  defp older_than(query, %Message{inserted_at: at, id: id}) do
    where(query, [m], m.inserted_at < ^at or (m.inserted_at == ^at and m.id < ^id))
  end

  @doc """
  Creates a message in `room` as the scope's user and broadcasts it to the
  room's subscribers. Guests (no user in scope) may not post.
  """
  def create_message(%Scope{user: %User{} = user}, room, attrs) do
    %Message{room: room, user_id: user.id, username: user.username}
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        Phoenix.PubSub.broadcast(@pubsub, topic(room), {:new_message, message})

        Phoenix.PubSub.broadcast(
          @pubsub,
          @rooms_topic,
          {:room_activity, room, message.inserted_at}
        )

        {:ok, message}

      error ->
        error
    end
  end

  def create_message(_scope, _room, _attrs), do: {:error, :unauthorized}

  @doc """
  Returns a changeset for tracking message form changes.
  """
  def change_message(%Message{} = message, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end

  defp topic(room), do: "room:" <> room
end
