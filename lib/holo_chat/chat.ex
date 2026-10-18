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
  Returns the most recent `limit` messages in `room`, oldest first.
  """
  def list_recent_messages(room, limit \\ 50) do
    Message
    |> where(room: ^room)
    |> order_by(desc: :inserted_at, desc: :id)
    |> limit(^limit)
    |> Repo.all()
    |> Enum.reverse()
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
