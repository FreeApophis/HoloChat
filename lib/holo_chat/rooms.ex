defmodule HoloChat.Rooms do
  @moduledoc """
  The Rooms context: rooms (channels), their game masters and their scene.

  A room exists as soon as someone posts. Whoever posts first in a new room
  becomes its game master and the room gets a record (`Room`); the lobby
  and rooms from before records had creators have none. A room's game
  masters can start a scenario from the library (see `HoloChat.Scenarios`)
  there: the room then plays that scene with its own cast, until they
  switch to another scenario or end it. Each change is announced in the
  chat.

  In any room, chat or role-play, a player can wear a library character as
  a cloak: they then post under its name and avatar. Whether a player may
  take over a character the AI plays in the room is the game masters' call.
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
  alias HoloChat.Rooms.{CastMember, Cloak, GameMaster, Room, Topic}

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
  Returns every role-play room that has a cast, as `{room, cast}` pairs,
  where the cast is the one the AI plays (see `list_ai_cast/1`). Rooms come
  with their scenario.
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

    Enum.map(rooms, &{&1, list_ai_cast(&1)})
  end

  @doc """
  Returns the rooms playing a scenario, with their scenario, newest first.
  """
  def list_roleplay_rooms do
    Room
    |> where([r], not is_nil(r.scenario_id))
    |> order_by(desc: :inserted_at, desc: :id)
    |> preload(:scenario)
    |> Repo.all()
  end

  @topic_max 200

  @doc """
  Returns the topic of the room called `name`, or nil.
  """
  def get_topic(name) do
    Repo.one(from t in Topic, where: t.room == ^name, select: t.topic)
  end

  @doc """
  Sets the topic of the room called `name` (blank clears it) for those who
  may moderate the room (see `can_moderate?/2`), so moderators also set the
  lobby's. Announces `{:topic_changed, name, topic}` to the room's
  subscribers (see `subscribe/1`) and returns `{:ok, topic}`.
  """
  def set_topic(scope, name, topic) when is_binary(topic) do
    topic = String.trim(topic)

    cond do
      not Chat.valid_room?(name) -> {:error, :invalid_room}
      not can_moderate?(scope, name) -> {:error, :unauthorized}
      String.length(topic) > @topic_max -> {:error, :too_long}
      true -> name |> store_topic(topic) |> broadcast_topic(name)
    end
  end

  defp store_topic(name, "") do
    Repo.delete_all(from t in Topic, where: t.room == ^name)
    nil
  end

  defp store_topic(name, topic) do
    Repo.insert!(%Topic{room: name, topic: topic},
      on_conflict: {:replace, [:topic, :updated_at]},
      conflict_target: :room
    )

    topic
  end

  defp broadcast_topic(topic, name) do
    Phoenix.PubSub.broadcast(@pubsub, topic(name), {:topic_changed, name, topic})
    {:ok, topic}
  end

  @languages [{"en", "English"}, {"de", "Deutsch"}]

  @doc """
  The languages a room can speak, as `{code, name}`, English first: the
  default, and the language of the lobby and record-less rooms.
  """
  def languages, do: @languages

  @doc """
  Returns every room for the room list: the lobby, rooms with messages and
  rooms with a record, most recently active first, as maps with `:name`,
  `:topic` (the room's own, or that of the scenario played there),
  `:scenario_title`, `:language`,
  `:game_masters` (`%{username:, avatar_id:}` by name) and `:last_message_at`.
  """
  def list_channels do
    activity = Chat.list_rooms()
    records = Map.new(Repo.all(from r in Room, preload: :scenario), &{&1.name, &1})

    masters =
      Repo.all(
        from gm in GameMaster,
          join: u in User,
          on: u.id == gm.user_id,
          order_by: u.username,
          select: {gm.room_id, %{username: u.username, avatar_id: u.avatar_id}}
      )
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    last_message_at = Map.new(activity, &{&1.name, &1.last_message_at})
    topics = Map.new(Repo.all(from t in Topic, select: {t.room, t.topic}))

    (Enum.map(activity, & &1.name) ++
       Enum.sort(Map.keys(records) ++ Map.keys(topics)) ++ ["lobby"])
    |> Enum.uniq()
    |> Enum.map(fn name ->
      room = records[name]
      scenario = room && room.scenario

      %{
        name: name,
        topic: topics[name] || (scenario && scenario.topic),
        scenario_title: scenario && scenario.title,
        language: if(room, do: room.language, else: "en"),
        game_masters: if(room, do: Map.get(masters, room.id, []), else: []),
        last_message_at: last_message_at[name]
      }
    end)
  end

  @doc """
  Returns up to `limit` rooms to recommend, one per scenario, as
  `%{room: room, players: count}` with the room's scenario.

  The rooms with the most players over the 7 days before `now` (since their
  scenario started) come first, then more messages; quiet rooms follow,
  most recently active first. See `HoloChat.Chat.player_activity/2`.
  """
  def list_destinations(limit, now \\ DateTime.utc_now()) do
    rooms = list_roleplay_rooms()
    activity = Chat.player_activity(Enum.map(rooms, & &1.name), DateTime.add(now, -7, :day))

    rooms
    |> Enum.map(&{&1, Map.fetch!(activity, &1.name)})
    |> Enum.sort_by(
      fn {room, a} -> {a.players, a.messages, unix_or_never(a.last_message_at), room.id} end,
      :desc
    )
    |> Enum.uniq_by(fn {room, _activity} -> room.scenario_id end)
    |> Enum.take(limit)
    |> Enum.map(fn {room, activity} -> %{room: room, players: activity.players} end)
  end

  defp unix_or_never(nil), do: -1
  defp unix_or_never(datetime), do: DateTime.to_unix(datetime, :microsecond)

  @doc """
  Returns the names of the rooms playing a scenario as a set.
  """
  def roleplay_room_names do
    Room
    |> where([r], not is_nil(r.scenario_id))
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
  Starts the scenario `scenario_id` in the room called `name`: a room with
  a record switches to it (see `switch_scenario/3`), any other room becomes
  a scene with the scope's user as its game master (see
  `create_roleplay_room/2`).
  """
  def start_scenario(scope, name, scenario_id) do
    case get_room(name) do
      nil -> create_roleplay_room(scope, %{"name" => name, "scenario_id" => scenario_id})
      room -> switch_scenario(scope, room, scenario_id)
    end
  end

  @doc """
  Creates a role-play room with the scope's user as its game master,
  playing the scenario `"scenario_id"` with its suggested cast. The scenario
  is announced in the chat.

  The name must be a valid room name that no room uses yet. Moderators and
  admins may turn an existing chat room other than the lobby into a scene.
  """
  def create_roleplay_room(%Scope{user: %User{} = user} = scope, attrs) do
    changeset =
      %Room{kind: "roleplay"}
      |> Room.create_changeset(attrs)
      |> Ecto.Changeset.validate_change(:name, fn :name, name ->
        validate_new_name(name, Accounts.moderator?(scope))
      end)

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

  # Names of existing role-play rooms are caught by the unique index.
  defp validate_new_name(name, moderator?) do
    cond do
      not Chat.valid_room?(name) ->
        [name: "may only contain lowercase letters, digits and dashes (up to 32)"]

      name == "lobby" or (Chat.room_used?(name) and not moderator?) ->
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
  Returns true if the scope may manage the room: its game masters,
  moderators and admins.
  """
  def can_manage?(scope, room), do: Accounts.moderator?(scope) or game_master?(scope, room)

  @doc """
  Updates the room's settings (how the cast takes turns, whether players
  may wear the cast's characters) and announces the change. Forbidding
  takes the cast's characters off the players who wear them.
  """
  def update_room(scope, %Room{} = room, attrs) do
    authorize(scope, room, fn ->
      room
      |> Room.changeset(attrs)
      |> Repo.update()
      |> enforce_cloak_policy()
      |> broadcast_update()
    end)
  end

  # Under "forbid", players who wear one of the AI's characters take it off.
  defp enforce_cloak_policy({:ok, %Room{cloak_policy: "forbid"} = room} = result) do
    cast = cast_ids(room)

    {_count, user_ids} =
      Repo.delete_all(
        from c in Cloak,
          where: c.room == ^room.name and c.character_id in ^cast,
          select: c.user_id
      )

    Enum.each(user_ids, &broadcast_cloak(room.name, &1))
    result
  end

  defp enforce_cloak_policy(result), do: result

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

  @doc """
  Ends the room's scenario: the cast leaves and the room is a chat room
  again, announced in the chat. Its game masters stay and can start another
  scenario with `switch_scenario/3`.
  """
  def end_scenario(scope, %Room{} = room) do
    authorize(scope, room, fn -> room |> stop_playing() |> announce_end(scope) end)
  end

  defp stop_playing(room) do
    Repo.transact(fn ->
      with {:ok, room} <- room |> Ecto.Changeset.change(scenario_id: nil) |> Repo.update() do
        replace_cast(room, [])
        {:ok, %{room | scenario: nil}}
      end
    end)
  end

  defp announce_end({:ok, room}, scope) do
    {:ok, _message} = Chat.create_scenario_end_message(scope, room.name)
    broadcast_update({:ok, room})
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
  Removes a game master. Game masters keep at least one; moderators and
  admins may also remove the last, leaving the room to them.
  """
  def remove_game_master(scope, %Room{} = room, user_id) do
    authorize(scope, room, fn ->
      if Accounts.moderator?(scope) do
        Repo.delete_all(
          from gm in GameMaster, where: gm.room_id == ^room.id and gm.user_id == ^user_id
        )

        :ok
      else
        room |> delete_game_master(user_id) |> ok_without_value()
      end
    end)
  end

  @doc """
  Returns true if the scope may delete messages in the room called `name`:
  its game masters, moderators and admins.
  """
  def can_moderate?(scope, name) do
    Accounts.moderator?(scope) or
      case get_room(name) do
        nil -> false
        room -> game_master?(scope, room)
      end
  end

  @doc """
  Deletes the message with the given id for those who may moderate its room
  (see `can_moderate?/2`). Scenario announcements stay: they mark where the
  cast's memory of a scenario begins.
  """
  def delete_message(scope, message_id) do
    with %Chat.Message{} = message <- Chat.get_message(message_id) || {:error, :not_found},
         true <- message.kind == "chat" || {:error, :announcement},
         true <- can_moderate?(scope, message.room) || {:error, :unauthorized} do
      Chat.delete_message(message)
    end
  end

  @doc """
  Makes the user with the given id a game master of the room called `name`,
  for moderators and admins. A room that has been used but has no record
  yet (an older chat room) gets one. The lobby has no game masters.
  """
  def appoint_game_master(scope, name, user_id) do
    cond do
      not Accounts.moderator?(scope) ->
        {:error, :unauthorized}

      name == "lobby" ->
        {:error, :lobby}

      true ->
        with %User{} = user <- Accounts.get_user(user_id) || {:error, :not_found},
             %Room{} = room <- get_room(name) || record_used_room(name) do
          Repo.insert!(%GameMaster{room_id: room.id, user_id: user.id}, on_conflict: :nothing)
          broadcast_update({:ok, room})
        end
    end
  end

  defp record_used_room(name) do
    if Chat.room_used?(name) do
      Repo.insert!(%Room{name: name, kind: "chat"}, on_conflict: :nothing)
      get_room(name)
    else
      {:error, :not_found}
    end
  end

  @doc """
  Returns the names of the rooms the user with the given id masters, by
  name.
  """
  def list_mastered_rooms(user_id) do
    Repo.all(
      from r in Room,
        join: gm in GameMaster,
        on: gm.room_id == r.id,
        where: gm.user_id == ^user_id,
        order_by: r.name,
        select: r.name
    )
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

  @doc """
  Returns the characters the AI plays in the room: the cast, except the
  characters players wear there.
  """
  def list_ai_cast(%Room{} = room) do
    worn = Repo.all(from c in Cloak, where: c.room == ^room.name, select: c.character_id)
    room |> cast_ids() |> Enum.reject(&(&1 in worn)) |> Characters.list_characters_by_ids()
  end

  ## Cloaks

  @doc """
  Puts on the library character `character_id` as the scope's cloak in the
  room called `name`, replacing any other cloak there, and announces it.

  Returns `{:error, :taken}` if another player wears it there, and
  `{:error, :cast}` if the AI plays it there and the game masters forbid
  taking it over.
  """
  def wear_character(%Scope{user: %User{} = user}, name, character_id) do
    with %{} = character <- Characters.get_character(character_id) || {:error, :not_found},
         :ok <- check_cloak_policy(name, character),
         {:ok, _cloak} <- put_cloak(user, name, character) do
      broadcast_cloak(name, user.id)
      {:ok, character}
    end
  end

  def wear_character(_scope, _name, _character_id), do: {:error, :unauthorized}

  defp check_cloak_policy(name, character) do
    case get_room(name) do
      %Room{cloak_policy: "forbid"} = room ->
        if character.id in cast_ids(room), do: {:error, :cast}, else: :ok

      _takeover_or_chat_room ->
        :ok
    end
  end

  defp put_cloak(user, name, character) do
    %Cloak{user_id: user.id, room: name, character_id: character.id}
    |> Cloak.changeset()
    |> Repo.insert(
      on_conflict: {:replace, [:character_id, :updated_at]},
      conflict_target: [:user_id, :room]
    )
    |> case do
      {:ok, cloak} -> {:ok, cloak}
      {:error, _changeset} -> {:error, :taken}
    end
  end

  @doc """
  Takes off the scope's cloak in the room called `name`, and announces it.
  """
  def take_off_cloak(%Scope{user: %User{} = user}, name) do
    Repo.delete_all(from c in Cloak, where: c.user_id == ^user.id and c.room == ^name)
    broadcast_cloak(name, user.id)
    :ok
  end

  def take_off_cloak(_scope, _name), do: {:error, :unauthorized}

  @doc """
  Returns the character the scope wears in the room called `name`, or nil.
  """
  def get_cloak(%Scope{user: %User{id: user_id}}, name) do
    Repo.one(
      from ch in Characters.Character,
        join: c in Cloak,
        on: c.character_id == ch.id,
        where: c.user_id == ^user_id and c.room == ^name
    )
  end

  def get_cloak(_scope, _name), do: nil

  @doc """
  Returns the characters worn in the room called `name`, by user id.
  """
  def list_cloaks(name) do
    cloaks = Repo.all(from c in Cloak, where: c.room == ^name)

    characters =
      Map.new(
        Characters.list_characters_by_ids(Enum.map(cloaks, & &1.character_id)),
        &{&1.id, &1}
      )

    Map.new(cloaks, &{&1.user_id, characters[&1.character_id]})
  end

  @doc """
  Posts a message in the room called `name` as the scope's user, in the
  name of the character they wear there (if any). See
  `HoloChat.Chat.create_message/4`.
  """
  def post_message(scope, name, attrs) do
    new_room? = name != "lobby" and not Chat.room_used?(name)

    result =
      case get_cloak(scope, name) do
        nil -> Chat.create_message(scope, name, attrs)
        character -> Chat.create_message(scope, name, attrs, character_id: character.id)
      end

    with {:ok, _message} <- result, true <- new_room?, do: claim_room(scope.user, name)
    result
  end

  # The first poster in a new room becomes its game master. Of two first
  # posts at once, the one that inserts the record wins.
  defp claim_room(user, name) do
    Repo.transact(fn ->
      case Repo.insert(%Room{name: name, kind: "chat"}, on_conflict: :nothing) do
        {:ok, %Room{id: nil}} ->
          {:ok, nil}

        {:ok, room} ->
          Repo.insert!(%GameMaster{room_id: room.id, user_id: user.id})
          {:ok, room}
      end
    end)
    |> case do
      {:ok, %Room{} = room} -> broadcast_update({:ok, room})
      {:ok, nil} -> :ok
    end
  end

  # Room subscribers update the player's look; the assistant reloads the
  # cast it plays, since a player may have taken over a character.
  defp broadcast_cloak(name, user_id) do
    Phoenix.PubSub.broadcast(@pubsub, topic(name), {:cloak_changed, user_id})
    Phoenix.PubSub.broadcast(@pubsub, @scenes_topic, {:scene_changed, name})
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
