defmodule HoloChat.RoomsTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.{Accounts, Assistant, Chat, Rooms, Scenarios}
  alias HoloChat.Rooms.Room
  alias HoloChat.Scenarios.Scenario

  describe "create_roleplay_room/2" do
    test "creates the room with the creator as its game master" do
      gm = user_scope_fixture()
      scenario = scenario_fixture(gm)
      name = unique_room()

      assert {:ok, %Room{name: ^name, kind: "roleplay"} = room} =
               Rooms.create_roleplay_room(gm, %{"name" => name, "scenario_id" => scenario.id})

      assert room.scenario_id == scenario.id
      assert Rooms.game_master?(gm, room)
      refute Rooms.game_master?(user_scope_fixture(), room)
      assert [%{id: id}] = Rooms.list_game_masters(room)
      assert id == gm.user.id
    end

    test "casts the scenario's suggested cast and announces the scenario" do
      gm = user_scope_fixture()
      scenario = scenario_fixture(gm, %{"title" => "Risa"})
      character = character_fixture(gm)
      {:ok, _} = Scenarios.cast_character(gm, scenario, character.id)

      room = roleplay_room_fixture(gm, %{"scenario_id" => scenario.id})

      assert [%{id: id}] = Rooms.list_cast(room)
      assert id == character.id

      assert [%{kind: "scenario", scenario_id: scenario_id, body: "Risa"}] =
               Chat.list_recent_messages(room.name)

      assert scenario_id == scenario.id
    end

    test "requires an account" do
      scenario = scenario_fixture(user_scope_fixture())

      assert {:error, :unauthorized} =
               Rooms.create_roleplay_room(nil, %{
                 "name" => unique_room(),
                 "scenario_id" => scenario.id
               })
    end

    test "validates the name and the scenario" do
      gm = user_scope_fixture()

      assert {:error, changeset} = Rooms.create_roleplay_room(gm, %{"name" => "Bad Name!"})
      assert %{name: [_], scenario_id: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               Rooms.create_roleplay_room(gm, %{"name" => unique_room(), "scenario_id" => "-1"})

      assert %{scenario_id: ["does not exist"]} = errors_on(changeset)
    end

    test "refuses names that are taken by role-play or chat rooms" do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)
      chat_room = unique_room()
      message_fixture(gm, chat_room)
      scenario = scenario_fixture(gm)

      for name <- [room.name, chat_room, "lobby"] do
        assert {:error, changeset} =
                 Rooms.create_roleplay_room(gm, %{"name" => name, "scenario_id" => scenario.id})

        assert %{name: ["is already taken"]} = errors_on(changeset)
      end
    end
  end

  describe "set_topic/3 and get_topic/1" do
    test "game masters and moderators set, change and clear a room's topic, announced" do
      gm = user_scope_fixture()
      room = unique_room()
      {:ok, _} = Rooms.post_message(gm, room, %{"body" => "mine"})
      Rooms.subscribe(room)

      assert {:ok, "Jazz only"} = Rooms.set_topic(gm, room, "  Jazz only ")
      assert Rooms.get_topic(room) == "Jazz only"
      assert_receive {:topic_changed, ^room, "Jazz only"}

      assert {:ok, "Blues too"} =
               Rooms.set_topic(role_scope_fixture(:moderator), room, "Blues too")

      assert {:ok, nil} = Rooms.set_topic(gm, room, " ")
      assert Rooms.get_topic(room) == nil
      assert_receive {:topic_changed, ^room, nil}
    end

    test "moderators set the lobby's topic and that of rooms nobody runs" do
      moderator = role_scope_fixture(:moderator)

      assert {:ok, "Welcome"} = Rooms.set_topic(moderator, "lobby", "Welcome")
      assert {:ok, "Quiet"} = Rooms.set_topic(moderator, unique_room(), "Quiet")
    end

    test "refuses players, guests, long topics and invalid rooms" do
      room = unique_room()
      {:ok, _} = Rooms.post_message(user_scope_fixture(), room, %{"body" => "first"})
      moderator = role_scope_fixture(:moderator)

      assert {:error, :unauthorized} = Rooms.set_topic(user_scope_fixture(), room, "Mine now")
      assert {:error, :unauthorized} = Rooms.set_topic(nil, room, "Mine now")
      assert {:error, :unauthorized} = Rooms.set_topic(user_scope_fixture(), "lobby", "Hi")
      assert {:error, :too_long} = Rooms.set_topic(moderator, room, String.duplicate("a", 201))
      assert {:error, :invalid_room} = Rooms.set_topic(moderator, "Not Valid", "x")
      assert Rooms.get_topic(room) == nil
    end

    test "list_channels/0 shows the room's topic before its scenario's" do
      gm = user_scope_fixture()
      scene = roleplay_room_fixture(gm, %{"topic" => "Sun and surf."})
      chat = unique_room()
      {:ok, _} = Rooms.set_topic(role_scope_fixture(:moderator), chat, "Chatter")

      assert %{topic: "Sun and surf."} =
               Enum.find(Rooms.list_channels(), &(&1.name == scene.name))

      {:ok, _} = Rooms.set_topic(gm, scene.name, "Party tonight")

      channels = Rooms.list_channels()
      assert %{topic: "Party tonight"} = Enum.find(channels, &(&1.name == scene.name))
      assert %{topic: "Chatter"} = Enum.find(channels, &(&1.name == chat))
    end
  end

  describe "list_channels/0" do
    test "lists the lobby, used rooms and scenes with topic and game masters, most active first" do
      gm = user_scope_fixture()
      co_gm = user_scope_fixture()
      scene = roleplay_room_fixture(gm, %{"title" => "Sunset Beach", "topic" => "Sun and surf."})
      {:ok, _} = Rooms.add_game_master(gm, scene, co_gm.user.username)
      chat = unique_room()
      {:ok, _} = Rooms.post_message(user_scope_fixture(), chat, %{"body" => "hi"})

      channels = Rooms.list_channels()
      names = Enum.map(channels, & &1.name)

      assert "lobby" in names
      assert Enum.filter(names, &(&1 in [chat, scene.name])) == [chat, scene.name]

      scene_channel = Enum.find(channels, &(&1.name == scene.name))
      assert scene_channel.topic == "Sun and surf."
      assert scene_channel.scenario_title == "Sunset Beach"

      assert Enum.map(scene_channel.game_masters, & &1.username) ==
               Enum.sort([gm.user.username, co_gm.user.username])

      assert %{avatar_id: nil} = hd(scene_channel.game_masters)

      # The first poster in a new room becomes its game master.
      chat_channel = Enum.find(channels, &(&1.name == chat))
      assert %{topic: nil, scenario_title: nil, game_masters: [_]} = chat_channel
    end
  end

  describe "list_destinations/2" do
    setup do
      %{gm: user_scope_fixture()}
    end

    defp say(scope, room), do: {:ok, _} = Rooms.post_message(scope, room.name, %{"body" => "Hi"})

    test "ranks rooms by players this week, then messages, one room per scenario",
         %{gm: gm} do
      few = roleplay_room_fixture(gm)
      many = roleplay_room_fixture(gm)
      same_scenario = roleplay_room_fixture(gm, %{"scenario_id" => many.scenario_id})
      for _ <- 1..3, do: say(user_scope_fixture(), many)
      for _ <- 1..2, do: say(user_scope_fixture(), same_scenario)
      chatty = user_scope_fixture()
      say(chatty, few)
      say(chatty, few)

      assert [first, second] = Rooms.list_destinations(2)
      assert {first.room.id, first.players} == {many.id, 3}
      assert {second.room.id, second.players} == {few.id, 1}
      assert first.room.scenario.id == many.scenario_id
    end

    test "tops up with recently active rooms and stops at the limit", %{gm: gm} do
      older = roleplay_room_fixture(gm)
      newer = roleplay_room_fixture(gm)

      assert [%{room: a, players: 0}, %{room: b, players: 0}] = Rooms.list_destinations(2)
      assert {a.id, b.id} == {newer.id, older.id}
      assert [_] = Rooms.list_destinations(1)
    end

    test "counts only the last 7 days", %{gm: gm} do
      room = roleplay_room_fixture(gm)
      say(user_scope_fixture(), room)

      assert [%{players: 1}] = Rooms.list_destinations(2)

      assert [%{players: 0}] =
               Rooms.list_destinations(2, DateTime.add(DateTime.utc_now(), 8, :day))
    end

    test "leaves out chat rooms" do
      say(user_scope_fixture(), %{name: unique_room()})

      assert Rooms.list_destinations(2) == []
    end
  end

  describe "start_scenario/3" do
    setup do
      gm = user_scope_fixture()
      scenario = scenario_fixture(gm, %{"title" => "Risa"})
      %{gm: gm, scenario: scenario}
    end

    test "opens a scene in a new channel, with the scope's user as game master",
         %{gm: gm, scenario: scenario} do
      name = unique_room()
      Chat.subscribe(name)

      assert {:ok, %Room{name: ^name, scenario: %Scenario{title: "Risa"}} = room} =
               Rooms.start_scenario(gm, name, scenario.id)

      assert Rooms.game_master?(gm, room)
      assert_receive {:new_message, %{kind: "scenario"}}
    end

    test "switches the scenario of a room its game masters run", %{gm: gm, scenario: scenario} do
      room = roleplay_room_fixture(gm)

      assert {:ok, %Room{scenario_id: id}} = Rooms.start_scenario(gm, room.name, scenario.id)
      assert id == scenario.id
      assert Rooms.get_room(room.name).id == room.id
    end

    test "refuses rooms run by other game masters", %{scenario: scenario} do
      room = roleplay_room_fixture(user_scope_fixture())

      assert {:error, :unauthorized} =
               Rooms.start_scenario(user_scope_fixture(), room.name, scenario.id)
    end

    test "leaves chat rooms without a game master and the lobby to admins",
         %{gm: gm, scenario: scenario} do
      chat_room = unique_room()
      message_fixture(gm, chat_room)

      for name <- [chat_room, "lobby"] do
        assert {:error, changeset} = Rooms.start_scenario(gm, name, scenario.id)
        assert %{name: ["is already taken"]} = errors_on(changeset)
      end

      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)

      assert {:ok, %Room{name: ^chat_room}} =
               Rooms.start_scenario(user_scope_fixture(admin), chat_room, scenario.id)
    end

    test "refuses unknown scenarios in a room", %{gm: gm} do
      room = roleplay_room_fixture(gm)
      assert {:error, :not_found} = Rooms.start_scenario(gm, room.name, "-1")
    end
  end

  describe "moderators" do
    test "manage any room and start scenarios in rooms nobody runs" do
      moderator = role_scope_fixture(:moderator)
      room = roleplay_room_fixture(user_scope_fixture())
      assert Rooms.can_manage?(moderator, room)

      chat_room = unique_room()
      message_fixture(user_scope_fixture(), chat_room)
      scenario = scenario_fixture(moderator)

      assert {:ok, %Room{name: ^chat_room}} =
               Rooms.start_scenario(moderator, chat_room, scenario.id)

      refute Rooms.can_manage?(role_scope_fixture(:library_editor), room)
    end
  end

  describe "appoint_game_master/3" do
    setup do
      %{admin: role_scope_fixture(:admin), user: user_fixture()}
    end

    test "makes a user game master of a room with a record", %{admin: admin, user: user} do
      room = roleplay_room_fixture(user_scope_fixture())

      assert {:ok, %Room{id: id}} = Rooms.appoint_game_master(admin, room.name, user.id)
      assert id == room.id
      assert Rooms.game_master?(user_scope_fixture(user), room)
    end

    test "gives an older chat room a record", %{admin: admin, user: user} do
      chat_room = unique_room()
      message_fixture(user_scope_fixture(), chat_room)

      assert {:ok, %Room{name: ^chat_room, scenario_id: nil} = room} =
               Rooms.appoint_game_master(admin, chat_room, user.id)

      assert Rooms.game_master?(user_scope_fixture(user), room)
    end

    test "refuses unused rooms, the lobby, unknown users and non-moderators",
         %{admin: admin, user: user} do
      assert {:error, :not_found} = Rooms.appoint_game_master(admin, unique_room(), user.id)
      assert {:error, :lobby} = Rooms.appoint_game_master(admin, "lobby", user.id)

      room = roleplay_room_fixture(user_scope_fixture())
      assert {:error, :not_found} = Rooms.appoint_game_master(admin, room.name, -1)

      assert {:error, :unauthorized} =
               Rooms.appoint_game_master(user_scope_fixture(), room.name, user.id)
    end

    test "moderators may appoint too", %{user: user} do
      room = roleplay_room_fixture(user_scope_fixture())

      assert {:ok, _room} =
               Rooms.appoint_game_master(role_scope_fixture(:moderator), room.name, user.id)
    end
  end

  describe "list_mastered_rooms/1" do
    test "returns the names of the rooms a user masters, by name" do
      gm = user_scope_fixture()
      first = roleplay_room_fixture(gm, %{"name" => "b" <> unique_room()})
      second = roleplay_room_fixture(gm, %{"name" => "a" <> unique_room()})
      roleplay_room_fixture(user_scope_fixture())

      assert Rooms.list_mastered_rooms(gm.user.id) == Enum.sort([first.name, second.name])
    end
  end

  describe "post_message/3 in a new channel" do
    test "makes the first poster its game master" do
      creator = user_scope_fixture()
      name = unique_room()
      Rooms.subscribe(name)

      assert {:ok, _message} = Rooms.post_message(creator, name, %{"body" => "First"})

      assert %Room{scenario_id: nil} = room = Rooms.get_room(name)
      assert Rooms.game_master?(creator, room)
      assert_receive {:room_updated, %Room{name: ^name}}

      other = user_scope_fixture()
      assert {:ok, _message} = Rooms.post_message(other, name, %{"body" => "Second"})
      refute Rooms.game_master?(other, room)
      refute name in Rooms.roleplay_room_names()
    end

    test "leaves the lobby and older chat rooms without a game master" do
      poster = user_scope_fixture()
      chat_room = unique_room()
      message_fixture(user_scope_fixture(), chat_room)

      for name <- ["lobby", chat_room] do
        assert {:ok, _message} = Rooms.post_message(poster, name, %{"body" => "Hi"})
        assert Rooms.get_room(name) == nil
      end
    end

    test "creates nothing when the message is invalid" do
      name = unique_room()

      assert {:error, _changeset} =
               Rooms.post_message(user_scope_fixture(), name, %{"body" => ""})

      assert Rooms.get_room(name) == nil
    end
  end

  describe "listing and getting rooms" do
    test "list_roleplay_rooms/0 returns the newest first, with their scenario" do
      gm = user_scope_fixture()
      first = roleplay_room_fixture(gm)
      second = roleplay_room_fixture(gm, %{"title" => "Second"})

      rooms = Rooms.list_roleplay_rooms()
      ids = Enum.map(rooms, & &1.id)
      assert Enum.find_index(ids, &(&1 == second.id)) < Enum.find_index(ids, &(&1 == first.id))
      assert %Scenario{title: "Second"} = Enum.find(rooms, &(&1.id == second.id)).scenario
    end

    test "get_room/1 finds a room by name with its scenario, or nil" do
      room = roleplay_room_fixture(user_scope_fixture(), %{"title" => "Keep"})

      assert %Room{id: id, scenario: %Scenario{title: "Keep"}} = Rooms.get_room(room.name)
      assert id == room.id
      assert Rooms.get_room(unique_room()) == nil
    end
  end

  describe "switch_scenario/3" do
    setup do
      gm = user_scope_fixture()
      old_character = character_fixture(gm)
      room = roleplay_room_fixture(gm)
      {:ok, _} = Rooms.cast_character(gm, room, old_character.id)

      scenario = scenario_fixture(gm, %{"title" => "Risa"})
      new_character = character_fixture(gm)
      {:ok, _} = Scenarios.cast_character(gm, scenario, new_character.id)

      %{gm: gm, room: room, scenario: scenario, new_character: new_character}
    end

    test "plays the new scenario with its cast and announces it",
         %{gm: gm, room: room, scenario: scenario, new_character: new_character} do
      Rooms.subscribe(room.name)
      Rooms.subscribe_scenes()
      Chat.subscribe(room.name)

      assert {:ok, %Room{scenario: %Scenario{title: "Risa"}} = updated} =
               Rooms.switch_scenario(gm, room, scenario.id)

      assert updated.scenario_id == scenario.id
      assert Rooms.get_room(room.name).scenario_id == scenario.id
      assert [%{id: id}] = Rooms.list_cast(updated)
      assert id == new_character.id

      assert_receive {:new_message, %{kind: "scenario", scenario_id: scenario_id}}
      assert scenario_id == scenario.id
      assert_receive {:room_updated, %Room{scenario_id: ^scenario_id}}
      # The scenes topic is global: wait for this room among other tests' rooms.
      name = room.name
      assert_receive {:scene_changed, ^name}
    end

    test "refuses players and unknown scenarios", %{gm: gm, room: room, scenario: scenario} do
      assert {:error, :unauthorized} =
               Rooms.switch_scenario(user_scope_fixture(), room, scenario.id)

      assert {:error, :not_found} = Rooms.switch_scenario(gm, room, "-1")
      assert Rooms.get_room(room.name).scenario_id == room.scenario_id
    end
  end

  describe "end_scenario/2" do
    setup do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)
      character = character_fixture(gm)
      {:ok, _} = Rooms.cast_character(gm, room, character.id)
      %{gm: gm, room: room}
    end

    test "leaves a chat room with its game masters, announced in the chat",
         %{gm: gm, room: room} do
      Chat.subscribe(room.name)
      Rooms.subscribe(room.name)

      assert {:ok, %Room{scenario_id: nil, scenario: nil}} = Rooms.end_scenario(gm, room)

      assert_receive {:new_message, %{kind: "scenario_end", scenario_id: nil}}
      assert_receive {:room_updated, %Room{scenario_id: nil}}
      ended = Rooms.get_room(room.name)
      assert Rooms.list_cast(ended) == []
      assert Rooms.game_master?(gm, ended)
      refute room.name in Rooms.roleplay_room_names()
      refute Enum.any?(Rooms.list_roleplay_rooms(), &(&1.id == room.id))
    end

    test "refuses players", %{room: room} do
      assert {:error, :unauthorized} = Rooms.end_scenario(user_scope_fixture(), room)
    end

    test "a new scenario can follow", %{gm: gm, room: room} do
      {:ok, room} = Rooms.end_scenario(gm, room)
      scenario = scenario_fixture(gm)

      assert {:ok, %Room{scenario_id: id}} = Rooms.switch_scenario(gm, room, scenario.id)
      assert id == scenario.id
      assert room.name in Rooms.roleplay_room_names()
    end
  end

  describe "create_roleplay_room/2 for an existing chat room" do
    test "is allowed for admins, but never for the lobby" do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      admin = user_scope_fixture(admin)
      scenario = scenario_fixture(admin)
      chat_room = unique_room()
      message_fixture(user_scope_fixture(), chat_room)

      assert {:ok, room} =
               Rooms.create_roleplay_room(admin, %{
                 "name" => chat_room,
                 "scenario_id" => scenario.id
               })

      assert Rooms.game_master?(admin, room)

      assert {:error, changeset} =
               Rooms.create_roleplay_room(admin, %{
                 "name" => "lobby",
                 "scenario_id" => scenario.id
               })

      assert %{name: ["is already taken"]} = errors_on(changeset)
    end
  end

  describe "update_room/3" do
    setup do
      gm = user_scope_fixture()
      %{gm: gm, room: roleplay_room_fixture(gm)}
    end

    test "lets game masters change the reply settings and announces it",
         %{gm: gm, room: room} do
      Rooms.subscribe(room.name)

      assert {:ok, %Room{reply_delay: 9}} = Rooms.update_room(gm, room, %{"reply_delay" => "9"})

      assert_receive {:room_updated, %Room{reply_delay: 9, scenario: %Scenario{}}}
    end

    test "never changes the name or the scenario", %{gm: gm, room: room} do
      other = scenario_fixture(gm)

      assert {:ok, %Room{name: name, scenario_id: scenario_id}} =
               Rooms.update_room(gm, room, %{"name" => "renamed", "scenario_id" => other.id})

      assert name == room.name
      assert scenario_id == room.scenario_id
    end

    test "lets admins manage any room", %{room: room} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)

      assert {:ok, _room} =
               Rooms.update_room(user_scope_fixture(admin), room, %{"reply_delay" => "1"})
    end

    test "refuses players and guests", %{room: room} do
      assert {:error, :unauthorized} =
               Rooms.update_room(user_scope_fixture(), room, %{"reply_delay" => "1"})

      assert {:error, :unauthorized} = Rooms.update_room(nil, room, %{"reply_delay" => "1"})
    end
  end

  describe "game masters" do
    setup do
      gm = user_scope_fixture()
      %{gm: gm, room: roleplay_room_fixture(gm)}
    end

    test "can add and remove other game masters", %{gm: gm, room: room} do
      other = user_fixture()

      assert {:ok, _user} = Rooms.add_game_master(gm, room, other.username)
      assert {:ok, _user} = Rooms.add_game_master(gm, room, other.username)
      assert Rooms.game_master?(user_scope_fixture(other), room)
      assert length(Rooms.list_game_masters(room)) == 2

      assert :ok = Rooms.remove_game_master(gm, room, other.id)
      refute Rooms.game_master?(user_scope_fixture(other), room)
    end

    test "cannot remove the last one", %{gm: gm, room: room} do
      assert {:error, :last_game_master} = Rooms.remove_game_master(gm, room, gm.user.id)
    end

    test "admins and moderators may remove the last one", %{gm: gm, room: room} do
      assert :ok = Rooms.remove_game_master(role_scope_fixture(:moderator), room, gm.user.id)
      assert Rooms.list_game_masters(room) == []
    end

    test "reports unknown users and refuses players", %{gm: gm, room: room} do
      assert {:error, :not_found} = Rooms.add_game_master(gm, room, "nobody-#{unique_username()}")

      assert {:error, :unauthorized} =
               Rooms.add_game_master(user_scope_fixture(), room, gm.user.username)
    end
  end

  describe "the cast" do
    setup do
      gm = user_scope_fixture()
      tag = unique_tag()
      %{gm: gm, tag: tag, room: roleplay_room_fixture(gm, %{"tag_list" => tag})}
    end

    test "game masters cast and uncast library characters, announcing it",
         %{gm: gm, room: room} do
      character = character_fixture(user_scope_fixture())
      Rooms.subscribe(room.name)

      assert {:ok, _room} = Rooms.cast_character(gm, room, character.id)
      assert {:ok, _room} = Rooms.cast_character(gm, room, character.id)
      assert_receive {:room_updated, _}
      assert [%{id: id}] = Rooms.list_cast(room)
      assert id == character.id

      assert {:ok, _room} = Rooms.uncast_character(gm, room, character.id)
      assert Rooms.list_cast(room) == []
    end

    test "players cannot change the cast", %{room: room} do
      character = character_fixture(user_scope_fixture())

      assert {:error, :unauthorized} =
               Rooms.cast_character(user_scope_fixture(), room, character.id)
    end

    test "suggest_cast/1 suggests characters tagged like the scenario, not yet cast",
         %{gm: gm, room: room, tag: tag} do
      cast = character_fixture(gm, %{"tag_list" => tag})
      fitting = character_fixture(gm, %{"tag_list" => tag})
      {:ok, _room} = Rooms.cast_character(gm, room, cast.id)

      assert Enum.map(Rooms.suggest_cast(Rooms.get_room(room.name)), & &1.id) == [fitting.id]
    end
  end

  describe "reply settings" do
    test "default to natural turns after four seconds, two AI turns in a row" do
      room = roleplay_room_fixture(user_scope_fixture())
      assert %Room{reply_policy: "natural", reply_delay: 4, max_ai_turns: 2} = room
    end

    test "are validated" do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)

      assert {:error, changeset} =
               Rooms.update_room(gm, room, %{
                 "reply_policy" => "chaos",
                 "reply_delay" => "99",
                 "max_ai_turns" => "0"
               })

      assert %{reply_policy: [_], reply_delay: [_], max_ai_turns: [_]} = errors_on(changeset)
    end
  end

  describe "list_staged_scenes/0 and subscribe_scenes/0" do
    test "list role-play rooms that have a cast, with their scenario and cast" do
      gm = user_scope_fixture()
      empty = roleplay_room_fixture(gm)
      staged = roleplay_room_fixture(gm, %{"title" => "Staged"})
      character = character_fixture(gm)
      {:ok, _} = Rooms.cast_character(gm, staged, character.id)

      scenes = Map.new(Rooms.list_staged_scenes(), fn {room, cast} -> {room.id, {room, cast}} end)

      assert {%Room{scenario: %Scenario{title: "Staged"}}, [%{id: id}]} = scenes[staged.id]
      assert id == character.id
      refute Map.has_key?(scenes, empty.id)
    end

    test "announce changes of any scene" do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)
      Rooms.subscribe_scenes()

      {:ok, _} = Rooms.update_room(gm, room, %{"reply_delay" => "1"})

      name = room.name
      assert_receive {:scene_changed, ^name}
    end
  end

  describe "cloaks" do
    setup do
      player = user_scope_fixture()
      riker = character_fixture(user_scope_fixture(), %{"name" => "Riker"})
      %{player: player, riker: riker, room: unique_room()}
    end

    test "a player wears a character in one room, then takes it off",
         %{player: player, riker: riker, room: room} do
      Rooms.subscribe(room)

      assert {:ok, %{id: id}} = Rooms.wear_character(player, room, riker.id)
      assert id == riker.id
      assert_receive {:cloak_changed, user_id}
      assert user_id == player.user.id

      assert %{name: "Riker"} = Rooms.get_cloak(player, room)
      assert Rooms.get_cloak(player, unique_room()) == nil
      assert %{^user_id => %{name: "Riker"}} = Rooms.list_cloaks(room)

      assert :ok = Rooms.take_off_cloak(player, room)
      assert Rooms.get_cloak(player, room) == nil
      assert_receive {:cloak_changed, ^user_id}
    end

    test "wearing another character replaces the cloak", %{
      player: player,
      riker: riker,
      room: room
    } do
      troi = character_fixture(player, %{"name" => "Troi"})
      {:ok, _} = Rooms.wear_character(player, room, riker.id)
      {:ok, _} = Rooms.wear_character(player, room, troi.id)

      assert %{name: "Troi"} = Rooms.get_cloak(player, room)
    end

    test "a character is worn by one player per room", %{player: player, riker: riker, room: room} do
      {:ok, _} = Rooms.wear_character(player, room, riker.id)

      assert {:error, :taken} = Rooms.wear_character(user_scope_fixture(), room, riker.id)
      assert {:ok, _} = Rooms.wear_character(user_scope_fixture(), unique_room(), riker.id)
    end

    test "guests and unknown characters are refused", %{riker: riker, room: room} do
      assert {:error, :unauthorized} = Rooms.wear_character(nil, room, riker.id)
      assert {:error, :not_found} = Rooms.wear_character(user_scope_fixture(), room, "-1")
    end

    test "post_message/3 posts in the worn character's name",
         %{player: player, riker: riker, room: room} do
      {:ok, plain} = Rooms.post_message(player, room, %{"body" => "Me."})
      {:ok, _} = Rooms.wear_character(player, room, riker.id)
      {:ok, cloaked} = Rooms.post_message(player, room, %{"body" => "Riker."})

      assert plain.character_id == nil
      assert cloaked.character_id == riker.id
      assert cloaked.user_id == player.user.id
      refute cloaked.from_assistant
    end
  end

  describe "cloaks and the AI cast" do
    setup do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)
      riker = character_fixture(gm)
      troi = character_fixture(gm)
      {:ok, _} = Rooms.cast_character(gm, room, riker.id)
      {:ok, _} = Rooms.cast_character(gm, room, troi.id)
      %{gm: gm, room: room, riker: riker, troi: troi}
    end

    test "by default a player takes a character over from the AI",
         %{room: room, riker: riker, troi: troi} do
      Rooms.subscribe_scenes()
      {:ok, _} = Rooms.wear_character(user_scope_fixture(), room.name, riker.id)

      name = room.name
      assert_receive {:scene_changed, ^name}
      assert Enum.map(Rooms.list_ai_cast(room), & &1.id) == [troi.id]
      assert length(Rooms.list_cast(room)) == 2

      scenes = Map.new(Rooms.list_staged_scenes(), fn {r, cast} -> {r.id, cast} end)
      assert Enum.map(scenes[room.id], & &1.id) == [troi.id]
    end

    test "game masters can forbid wearing the AI's characters",
         %{gm: gm, room: room, riker: riker} do
      assert room.cloak_policy == "takeover"
      {:ok, room} = Rooms.update_room(gm, room, %{"cloak_policy" => "forbid"})

      assert {:error, :cast} = Rooms.wear_character(user_scope_fixture(), room.name, riker.id)

      assert {:error, changeset} = Rooms.update_room(gm, room, %{"cloak_policy" => "chaos"})
      assert %{cloak_policy: [_]} = errors_on(changeset)
    end

    test "game masters choose the room's language", %{gm: gm, room: room} do
      assert room.language == "en"
      assert {"de", "Deutsch"} in Rooms.languages()

      {:ok, room} = Rooms.update_room(gm, room, %{"language" => "de"})
      assert room.language == "de"
      assert %{language: "de"} = Enum.find(Rooms.list_channels(), &(&1.name == room.name))
      # The lobby and rooms without a record are open to any language.
      assert %{language: nil} = Enum.find(Rooms.list_channels(), &(&1.name == "lobby"))

      assert {:error, changeset} = Rooms.update_room(gm, room, %{"language" => "xx"})
      assert %{language: [_]} = errors_on(changeset)

      # No language: multilingual, like the lobby.
      {:ok, room} = Rooms.update_room(gm, room, %{"language" => ""})
      assert room.language == nil
      assert %{language: nil} = Enum.find(Rooms.list_channels(), &(&1.name == room.name))
    end

    test "game masters choose a prompt template for the cast", %{gm: gm, room: room} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)

      {:ok, template} =
        Assistant.create_prompt_template(user_scope_fixture(admin), %{
          "name" => "Rhymes #{System.unique_integer([:positive])}",
          "body" => "Rhyme, {{char}}."
        })

      {:ok, room} = Rooms.update_room(gm, room, %{"prompt_template_id" => template.id})
      assert room.prompt_template_id == template.id

      assert {:error, changeset} = Rooms.update_room(gm, room, %{"prompt_template_id" => "-1"})
      assert %{prompt_template_id: ["does not exist"]} = errors_on(changeset)
    end

    test "forbidding takes the AI's characters off the players who wear them",
         %{gm: gm, room: room, riker: riker, troi: troi} do
      player = user_scope_fixture()
      bystander = user_scope_fixture()
      {:ok, _} = Rooms.wear_character(player, room.name, riker.id)
      {:ok, _} = Rooms.wear_character(bystander, room.name, character_fixture(gm).id)
      Rooms.subscribe(room.name)
      Rooms.subscribe_scenes()

      {:ok, _room} = Rooms.update_room(gm, room, %{"cloak_policy" => "forbid"})

      assert Rooms.get_cloak(player, room.name) == nil
      assert Rooms.get_cloak(bystander, room.name)
      user_id = player.user.id
      assert_receive {:cloak_changed, ^user_id}
      name = room.name
      assert_receive {:scene_changed, ^name}

      assert Enum.sort(Enum.map(Rooms.list_ai_cast(room), & &1.id)) ==
               Enum.sort([riker.id, troi.id])
    end
  end

  describe "delete_message/2" do
    setup do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)
      message = message_fixture(user_scope_fixture(), room.name)
      %{gm: gm, room: room, message: message}
    end

    test "lets the room's game masters delete messages", %{gm: gm, room: room, message: message} do
      assert {:ok, _message} = Rooms.delete_message(gm, message.id)
      refute Enum.any?(Chat.list_recent_messages(room.name), &(&1.id == message.id))
    end

    test "lets moderators delete messages in any room, the lobby included", %{message: message} do
      moderator = role_scope_fixture(:moderator)
      assert {:ok, _message} = Rooms.delete_message(moderator, message.id)

      in_lobby = message_fixture(user_scope_fixture(), "lobby")
      assert {:ok, _message} = Rooms.delete_message(moderator, in_lobby.id)
    end

    test "refuses players, even the author", %{message: message} do
      assert {:error, :unauthorized} = Rooms.delete_message(user_scope_fixture(), message.id)

      author = %HoloChat.Accounts.Scope{user: Accounts.get_user!(message.user_id)}
      assert {:error, :unauthorized} = Rooms.delete_message(author, message.id)
      assert {:error, :unauthorized} = Rooms.delete_message(nil, message.id)
    end

    test "keeps scenario announcements and reports unknown messages", %{gm: gm, room: room} do
      [announcement] =
        room.name |> Chat.list_recent_messages() |> Enum.filter(&(&1.kind == "scenario"))

      assert {:error, :announcement} = Rooms.delete_message(gm, announcement.id)
      assert {:error, :not_found} = Rooms.delete_message(gm, -1)
    end
  end

  describe "can_moderate?/2" do
    test "holds for the room's game masters and for moderators" do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)

      assert Rooms.can_moderate?(gm, room.name)
      assert Rooms.can_moderate?(role_scope_fixture(:moderator), unique_room())
      refute Rooms.can_moderate?(user_scope_fixture(), room.name)
      refute Rooms.can_moderate?(gm, unique_room())
      refute Rooms.can_moderate?(nil, room.name)
    end
  end
end
