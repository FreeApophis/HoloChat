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
  @max_body_length 2000
  @room_format ~r/\A[a-z0-9][a-z0-9-]{0,31}\z/

  @doc """
  Returns true if `room` is a valid room name: lowercase letters,
  digits and dashes, up to 32 characters, not starting with a dash.
  """
  def valid_room?(room) when is_binary(room), do: Regex.match?(@room_format, room)
  def valid_room?(_), do: false

  @doc """
  Returns true if `room` is in use as a chat room: it has messages, or it is
  the lobby.
  """
  def room_used?("lobby"), do: true
  def room_used?(room), do: Repo.exists?(from m in Message, where: m.room == ^room)

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
      |> preload(user: ^author_query())
      |> Repo.all()

    {messages |> Enum.take(limit) |> Enum.reverse(), length(messages) > limit}
  end

  # Authors come with their public fields only, so password hashes never
  # travel with messages into LiveViews or over PubSub.
  defp author_query, do: from(u in User, select: struct(u, [:id, :username, :avatar_id]))

  defp older_than(query, nil), do: query

  defp older_than(query, %Message{inserted_at: at, id: id}) do
    where(query, [m], m.inserted_at < ^at or (m.inserted_at == ^at and m.id < ^id))
  end

  @doc """
  Creates a message in `room` as the scope's user and broadcasts it to the
  room's subscribers. Guests (no user in scope) may not post.

  Pass `character_id:` for the character the user wears in the room (see
  `HoloChat.Rooms.post_message/3`).
  """
  def create_message(scope, room, attrs, opts \\ [])

  def create_message(%Scope{user: %User{} = user}, room, attrs, opts) do
    %Message{
      room: room,
      user_id: user.id,
      username: user.username,
      character_id: opts[:character_id]
    }
    |> Message.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = Repo.preload(message, user: author_query())
        broadcast_new_message(message)
        {:ok, message}

      error ->
        error
    end
  end

  def create_message(_scope, _room, _attrs, _opts), do: {:error, :unauthorized}

  @doc """
  Announces in `room` that it now plays the scenario `scenario_id`, as the
  scope's user. The `title` is the message body, for clients that don't
  look the scenario up.
  """
  def create_scenario_message(%Scope{user: %User{}} = scope, room, scenario_id, title) do
    create_announcement(scope, room, "scenario", scenario_id, title)
  end

  def create_scenario_message(_scope, _room, _scenario_id, _title), do: {:error, :unauthorized}

  @doc """
  Announces in `room` that its scenario has ended, as the scope's user.
  """
  def create_scenario_end_message(%Scope{user: %User{}} = scope, room) do
    create_announcement(scope, room, "scenario_end", nil, "The scenario has ended.")
  end

  def create_scenario_end_message(_scope, _room), do: {:error, :unauthorized}

  defp create_announcement(%Scope{user: user}, room, kind, scenario_id, body) do
    %Message{
      room: room,
      user_id: user.id,
      username: user.username,
      kind: kind,
      scenario_id: scenario_id
    }
    |> Message.changeset(%{body: body})
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        message = Repo.preload(message, user: author_query())
        broadcast_new_message(message)
        {:ok, message}

      error ->
        error
    end
  end

  defp broadcast_new_message(%Message{room: room} = message) do
    Phoenix.PubSub.broadcast(@pubsub, topic(room), {:new_message, message})
    Phoenix.PubSub.broadcast(@pubsub, @rooms_topic, {:room_activity, room, message.inserted_at})
  end

  @doc """
  Posts a reply from the AI assistant named `name` and broadcasts it.

  Replies longer than a message may be are shortened. Pass `persona_id:` to
  record which persona wrote it.
  """
  def create_assistant_message(room, name, body, opts \\ []) do
    %Message{room: room, username: name, from_assistant: true, persona_id: opts[:persona_id]}
    |> Message.changeset(%{body: truncate(body, @max_body_length)})
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        broadcast_new_message(message)
        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Posts a message written by the cast character `character_id` (played by
  the model) under its `name`, and broadcasts it.
  """
  def create_character_message(room, name, body, character_id) do
    %Message{room: room, username: name, from_assistant: true, character_id: character_id}
    |> Message.changeset(%{body: truncate(body, @max_body_length)})
    |> Repo.insert()
    |> case do
      {:ok, message} ->
        broadcast_new_message(message)
        {:ok, message}

      error ->
        error
    end
  end

  defp truncate(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  @doc """
  Returns a changeset for tracking message form changes.
  """
  def change_message(%Message{} = message, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end

  defp topic(room), do: "room:" <> room
end
