defmodule HoloChat.RoomsTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.{Accounts, Chat, Rooms, Scenarios}
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
end
