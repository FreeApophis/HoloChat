defmodule HoloChat.Rooms do
  @moduledoc """
  The Rooms context: role-play rooms, their game masters and their scene.

  Plain chat rooms need no record; they exist as soon as someone posts.
  A role-play room has one, holding the scene (title, topic line, scenario,
  card and background image) that its game masters edit.
  """

  use Boundary,
    deps: [HoloChat.Repo, HoloChat.Accounts, HoloChat.Avatars, HoloChat.Characters, HoloChat.Chat],
    exports: [Room]

  import Ecto.Query, warn: false

  alias HoloChat.{Accounts, Avatars, Characters, Chat}
  alias HoloChat.Accounts.{Scope, User}
  alias HoloChat.Repo
  alias HoloChat.Rooms.{CastMember, GameMaster, Room}

  @pubsub HoloChat.PubSub
  @image_sizes %{card: {640, 360}, background: {1600, 900}}

  @doc """
  Subscribes the calling process to changes of the room called `name`.

  Subscribers receive `{:room_updated, %Room{}}`.
  """
  def subscribe(name), do: Phoenix.PubSub.subscribe(@pubsub, topic(name))

  @doc """
  Stops receiving changes of the room called `name`.
  """
  def unsubscribe(name), do: Phoenix.PubSub.unsubscribe(@pubsub, topic(name))

  @doc """
  Returns all role-play rooms, newest first.
  """
  def list_roleplay_rooms do
    Room
    |> where(kind: "roleplay")
    |> order_by(desc: :inserted_at, desc: :id)
    |> Repo.all()
  end

  @doc """
  Returns the names of all role-play rooms as a set.
  """
  def roleplay_room_names do
    Room
    |> where(kind: "roleplay")
    |> select([r], r.name)
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Gets the room called `name`, or nil if it has no record.
  """
  def get_room(name) when is_binary(name), do: Repo.get_by(Room, name: name)

  @doc """
  Creates a role-play room with the scope's user as its game master.

  The name must be a valid room name that no chat or role-play room uses yet.
  """
  def create_roleplay_room(%Scope{user: %User{} = user}, attrs) do
    changeset =
      %Room{kind: "roleplay"}
      |> Room.create_changeset(attrs)
      |> Ecto.Changeset.validate_change(:name, &validate_new_name/2)

    Repo.transact(fn ->
      with {:ok, room} <- Repo.insert(changeset) do
        Repo.insert!(%GameMaster{room_id: room.id, user_id: user.id})
        {:ok, room}
      end
    end)
  end

  def create_roleplay_room(_scope, _attrs), do: {:error, :unauthorized}

  defp validate_new_name(:name, name) do
    cond do
      not Chat.valid_room?(name) ->
        [name: "may only contain lowercase letters, digits and dashes (up to 32)"]

      Chat.room_used?(name) ->
        [name: "is already taken"]

      true ->
        []
    end
  end

  @doc """
  Returns a changeset for creating a room (`nil` room) or editing its scene.
  """
  def change_room(room, attrs \\ %{})
  def change_room(nil, attrs), do: Room.create_changeset(%Room{}, attrs)

  def change_room(%Room{} = room, attrs) do
    room
    |> Map.put(:tag_list, room.tag_list || Characters.Tags.format(room.tags))
    |> Room.changeset(attrs)
  end

  @doc """
  Returns true if the scope's user is one of the room's game masters.
  """
  def game_master?(%Scope{user: %User{id: user_id}}, %Room{id: room_id}) do
    Repo.exists?(from gm in GameMaster, where: gm.room_id == ^room_id and gm.user_id == ^user_id)
  end

  def game_master?(_scope, _room), do: false

  @doc """
  Returns true if the scope may manage the room: its game masters and admins.
  """
  def can_manage?(scope, room), do: Accounts.admin?(scope) or game_master?(scope, room)

  @doc """
  Updates the scene (title, topic, scenario) and announces the change.
  """
  def update_room(scope, %Room{} = room, attrs) do
    authorize(scope, room, fn ->
      room |> Room.changeset(attrs) |> Repo.update() |> broadcast_update()
    end)
  end

  @doc """
  Replaces the room's `:card` (640x360) or `:background` (1600x900) image
  with an uploaded one, deleting the old image.
  """
  def update_room_image(scope, %Room{} = room, kind, image)
      when is_map_key(@image_sizes, kind) and is_binary(image) do
    authorize(scope, room, fn ->
      room |> replace_image(image_field(kind), @image_sizes[kind], image) |> broadcast_update()
    end)
  end

  defp replace_image(room, field, size, image) do
    Repo.transact(fn ->
      with {:ok, new_image} <- Avatars.create_avatar(image, size),
           {:ok, updated} <-
             room |> Ecto.Changeset.change([{field, new_image.id}]) |> Repo.update() do
        :ok = Avatars.delete_avatar(Map.fetch!(room, field))
        {:ok, updated}
      end
    end)
  end

  defp image_field(:card), do: :card_image_id
  defp image_field(:background), do: :background_image_id

  @doc """
  Returns the room's game masters with their public fields, by name.
  """
  def list_game_masters(%Room{id: room_id}) do
    Repo.all(
      from u in User,
        join: gm in GameMaster,
        on: gm.user_id == u.id,
        where: gm.room_id == ^room_id,
        order_by: u.username,
        select: struct(u, [:id, :username, :avatar_id])
    )
  end

  @doc """
  Makes the user called `username` a game master of the room as well.
  Adding someone twice is harmless.
  """
  def add_game_master(scope, %Room{} = room, username) do
    authorize(scope, room, fn ->
      case Accounts.get_user_by_username(String.trim(username)) do
        nil ->
          {:error, :not_found}

        user ->
          Repo.insert!(%GameMaster{room_id: room.id, user_id: user.id}, on_conflict: :nothing)
          {:ok, user}
      end
    end)
  end

  @doc """
  Removes a game master. Every room keeps at least one.
  """
  def remove_game_master(scope, %Room{} = room, user_id) do
    authorize(scope, room, fn ->
      room |> delete_game_master(user_id) |> ok_without_value()
    end)
  end

  defp ok_without_value({:ok, _value}), do: :ok
  defp ok_without_value(error), do: error

  # Locks the room's game masters so two concurrent removals can't both
  # pass the check and leave the room without any.
  defp delete_game_master(room, user_id) do
    Repo.transact(fn ->
      masters = from gm in GameMaster, where: gm.room_id == ^room.id

      case Repo.all(lock(masters, "FOR UPDATE")) do
        [_only_one] ->
          {:error, :last_game_master}

        _several ->
          Repo.delete_all(from gm in masters, where: gm.user_id == ^user_id)
          {:ok, :removed}
      end
    end)
  end

  @doc """
  Returns the characters cast in the room, by name.
  """
  def list_cast(%Room{} = room), do: Characters.list_characters_by_ids(cast_ids(room))

  @doc """
  Suggests library characters for the room: those sharing its tags, most
  shared tags first, leaving out the ones already cast.
  """
  def suggest_cast(%Room{} = room, limit \\ 12) do
    Characters.suggest_characters(room.tags, cast_ids(room), limit)
  end

  @doc """
  Casts a library character in the room and announces the change. Casting
  someone twice is harmless.
  """
  def cast_character(scope, %Room{} = room, character_id) do
    authorize(scope, room, fn ->
      case Characters.get_character(character_id) do
        nil ->
          {:error, :not_found}

        character ->
          Repo.insert!(%CastMember{room_id: room.id, character_id: character.id},
            on_conflict: :nothing
          )

          broadcast_update({:ok, room})
      end
    end)
  end

  @doc """
  Removes a character from the room's cast and announces the change.
  """
  def uncast_character(scope, %Room{} = room, character_id) do
    authorize(scope, room, fn ->
      Repo.delete_all(
        from cm in CastMember,
          where: cm.room_id == ^room.id and cm.character_id == ^character_id
      )

      broadcast_update({:ok, room})
    end)
  end

  defp cast_ids(%Room{id: room_id}) do
    Repo.all(from cm in CastMember, where: cm.room_id == ^room_id, select: cm.character_id)
  end

  defp authorize(scope, room, fun) do
    if can_manage?(scope, room), do: fun.(), else: {:error, :unauthorized}
  end

  defp broadcast_update({:ok, %Room{} = room} = result) do
    Phoenix.PubSub.broadcast(@pubsub, topic(room.name), {:room_updated, room})
    result
  end

  defp broadcast_update(error), do: error

  defp topic(name), do: "scene:" <> name
end
