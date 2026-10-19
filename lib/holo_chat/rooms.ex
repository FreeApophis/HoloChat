defmodule HoloChat.Rooms do
  @moduledoc """
  The Rooms context: role-play rooms, their game masters and their scene.

  Plain chat rooms need no record; they exist as soon as someone posts.
  A role-play room has one. It plays one scenario from the library (see
  `HoloChat.Scenarios`) at a time with its own cast, and its game masters
  can switch to another scenario; each switch is announced in the chat.
  """

  use Boundary,
    deps: [
      HoloChat.Repo,
      HoloChat.Accounts,
      HoloChat.Characters,
      HoloChat.Chat,
      HoloChat.Scenarios
    ],
    exports: [Room]

  import Ecto.Query, warn: false

  alias HoloChat.{Accounts, Characters, Chat, Scenarios}
  alias HoloChat.Accounts.{Scope, User}
  alias HoloChat.Repo
  alias HoloChat.Rooms.{CastMember, GameMaster, Room}

  @pubsub HoloChat.PubSub
  @scenes_topic "scenes"

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
  Subscribes the calling process to changes of any scene (its settings or
  cast). Subscribers receive `{:scene_changed, name}`.
  """
  def subscribe_scenes, do: Phoenix.PubSub.subscribe(@pubsub, @scenes_topic)

  @doc """
  Returns every role-play room that has a cast, as `{room, cast}` pairs.
  Rooms come with their scenario.
  """
  def list_staged_scenes do
    rooms =
      Repo.all(
        from r in Room,
          join: cm in CastMember,
          on: cm.room_id == r.id,
          distinct: true,
          preload: :scenario
      )

    Enum.map(rooms, &{&1, list_cast(&1)})
  end

  @doc """
  Returns all role-play rooms with their scenario, newest first.
  """
  def list_roleplay_rooms do
    Room
    |> where(kind: "roleplay")
    |> order_by(desc: :inserted_at, desc: :id)
    |> preload(:scenario)
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
  Gets the room called `name` with its scenario, or nil if it has no record.
  """
  def get_room(name) when is_binary(name) do
    Room |> Repo.get_by(name: name) |> Repo.preload(:scenario)
  end

  @doc """
  Creates a role-play room with the scope's user as its game master,
  playing the scenario `"scenario_id"` with its suggested cast. The scenario
  is announced in the chat.

  The name must be a valid room name that no chat or role-play room uses yet.
  """
  def create_roleplay_room(%Scope{user: %User{} = user} = scope, attrs) do
    changeset =
      %Room{kind: "roleplay"}
      |> Room.create_changeset(attrs)
      |> Ecto.Changeset.validate_change(:name, &validate_new_name/2)

    Repo.transact(fn ->
      with {:ok, room} <- Repo.insert(changeset) do
        Repo.insert!(%GameMaster{room_id: room.id, user_id: user.id})
        room = Repo.preload(room, :scenario)
        replace_cast(room, Scenarios.list_cast(room.scenario))
        {:ok, room}
      end
    end)
    |> announce_scenario(scope)
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
  Returns a changeset for creating a room (`nil` room) or editing its
  settings.
  """
  def change_room(room, attrs \\ %{})
  def change_room(nil, attrs), do: Room.create_changeset(%Room{}, attrs)
  def change_room(%Room{} = room, attrs), do: Room.changeset(room, attrs)

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
  Updates the room's settings (how the cast takes turns) and announces the
  change.
  """
  def update_room(scope, %Room{} = room, attrs) do
    authorize(scope, room, fn ->
      room |> Room.changeset(attrs) |> Repo.update() |> broadcast_update()
    end)
  end

  @doc """
  Makes the room play another scenario: its suggested cast replaces the
  room's cast, and the change is announced in the chat. From then on the
  cast only remembers what happened since (see `HoloChat.Assistant`).
  """
  def switch_scenario(scope, %Room{} = room, scenario_id) do
    authorize(scope, room, fn ->
      case Scenarios.get_scenario(scenario_id) do
        nil -> {:error, :not_found}
        scenario -> room |> play(scenario) |> announce_scenario(scope)
      end
    end)
  end

  defp play(room, scenario) do
    Repo.transact(fn ->
      with {:ok, room} <-
             room |> Ecto.Changeset.change(scenario_id: scenario.id) |> Repo.update() do
        replace_cast(room, Scenarios.list_cast(scenario))
        {:ok, %{room | scenario: scenario}}
      end
    end)
  end

  defp replace_cast(room, characters) do
    Repo.delete_all(from cm in CastMember, where: cm.room_id == ^room.id)

    Repo.insert_all(
      CastMember,
      for(c <- characters, do: %{room_id: room.id, character_id: c.id, inserted_at: now()})
    )
  end

  defp now, do: DateTime.utc_now(:second)

  # After the transaction, so the room is committed when listeners react.
  defp announce_scenario({:ok, room}, scope) do
    {:ok, _message} =
      Chat.create_scenario_message(scope, room.name, room.scenario.id, room.scenario.title)

    broadcast_update({:ok, room})
  end

  defp announce_scenario(error, _scope), do: error

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
  Suggests library characters for the room: those sharing its scenario's
  tags, most shared tags first, leaving out the ones already cast.
  """
  def suggest_cast(%Room{} = room, limit \\ 12) do
    tags =
      case Repo.preload(room, :scenario).scenario do
        nil -> []
        scenario -> scenario.tags
      end

    Characters.suggest_characters(tags, cast_ids(room), limit)
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

  # Listeners get the room with its scenario.
  defp broadcast_update({:ok, %Room{} = room}) do
    room = Repo.preload(room, :scenario)
    Phoenix.PubSub.broadcast(@pubsub, topic(room.name), {:room_updated, room})
    Phoenix.PubSub.broadcast(@pubsub, @scenes_topic, {:scene_changed, room.name})
    {:ok, room}
  end

  defp broadcast_update(error), do: error

  defp topic(name), do: "scene:" <> name
end
