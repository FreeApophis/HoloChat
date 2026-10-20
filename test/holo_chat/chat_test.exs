defmodule HoloChat.ChatTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.Chat
  alias HoloChat.Chat.Message

  setup do
    %{scope: user_scope_fixture(), room: unique_room()}
  end

  describe "create_message/3" do
    test "stores the message as the scope's user and broadcasts it",
         %{scope: scope, room: room} do
      Chat.subscribe(room)

      assert {:ok, %Message{} = message} =
               Chat.create_message(scope, room, %{"body" => " hello "})

      assert message.room == room
      assert message.user_id == scope.user.id
      assert message.username == scope.user.username
      assert message.body == "hello"
      assert_receive {:new_message, ^message}
    end

    test "ignores username, user and room passed in params", %{scope: scope, room: room} do
      {:ok, message} =
        Chat.create_message(scope, room, %{
          "body" => "hi",
          "username" => "mallory",
          "user_id" => -1,
          "room" => "secret"
        })

      assert message.username == scope.user.username
      assert message.user_id == scope.user.id
      assert message.room == room
    end

    test "does not broadcast to other rooms", %{scope: scope, room: room} do
      Chat.subscribe(unique_room())
      {:ok, _} = Chat.create_message(scope, room, %{"body" => "hi"})
      refute_receive {:new_message, _}
    end

    test "requires a non-blank body", %{scope: scope, room: room} do
      assert {:error, changeset} = Chat.create_message(scope, room, %{"body" => "   "})
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "refuses guests", %{room: room} do
      assert {:error, :unauthorized} = Chat.create_message(nil, room, %{"body" => "hi"})
    end
  end

  describe "create_assistant_message/4" do
    test "records which persona wrote the message", %{room: room} do
      {:ok, admin} = HoloChat.Accounts.set_admin(user_fixture().username, true)

      {:ok, holo} =
        HoloChat.Assistant.create_persona(user_scope_fixture(admin), %{"name" => "Holo"})

      {:ok, message} = Chat.create_assistant_message(room, "Holo", "Hi", persona_id: holo.id)
      assert message.persona_id == holo.id
    end
  end

  describe "create_assistant_message/3" do
    test "stores and broadcasts a message from the assistant", %{room: room} do
      Chat.subscribe(room)

      assert {:ok, %Message{} = message} =
               Chat.create_assistant_message(room, "Holo", "Hi there!")

      assert message.from_assistant
      assert message.username == "Holo"
      assert is_nil(message.user_id)
      assert_receive {:new_message, ^message}
    end

    test "shortens replies that are too long", %{room: room} do
      {:ok, message} = Chat.create_assistant_message(room, "Holo", String.duplicate("a", 3000))

      assert String.length(message.body) == 2000
      assert String.ends_with?(message.body, "…")
    end

    test "messages from people are not from the assistant", %{scope: scope, room: room} do
      refute message_fixture(scope, room).from_assistant
    end
  end

  describe "list_recent_messages/2" do
    test "returns only the room's messages, oldest first, capped at the limit",
         %{scope: scope, room: room} do
      for n <- 1..3, do: message_fixture(scope, room, %{"body" => "m#{n}"})
      message_fixture(scope, unique_room(), %{"body" => "elsewhere"})

      assert ["m2", "m3"] == Enum.map(Chat.list_recent_messages(room, 2), & &1.body)
    end
  end

  describe "message authors" do
    test "come with their public profile fields only", %{scope: scope, room: room} do
      Chat.subscribe(room)
      message_fixture(scope, room)

      assert_receive {:new_message, broadcast}
      [listed] = Chat.list_recent_messages(room)

      for message <- [broadcast, listed] do
        assert message.user.id == scope.user.id
        assert message.user.username == scope.user.username
        assert Map.has_key?(message.user, :avatar_id)
        assert message.user.hashed_password == nil
      end
    end
  end

  describe "list_messages_page/3" do
    setup %{scope: scope, room: room} do
      messages = for n <- 1..5, do: message_fixture(scope, room, %{"body" => "m#{n}"})
      %{messages: messages}
    end

    test "without a cursor returns the latest page, oldest first", %{room: room} do
      assert {page, true} = Chat.list_messages_page(room, nil, 2)
      assert Enum.map(page, & &1.body) == ["m4", "m5"]
    end

    test "returns the page before a message and says when history ends",
         %{room: room, messages: messages} do
      assert {page, true} = Chat.list_messages_page(room, Enum.at(messages, 3), 2)
      assert Enum.map(page, & &1.body) == ["m2", "m3"]

      assert {page, false} = Chat.list_messages_page(room, Enum.at(messages, 1), 2)
      assert Enum.map(page, & &1.body) == ["m1"]
    end

    test "pages through equal timestamps without gaps or repeats", %{room: room} do
      Repo.update_all(HoloChat.Chat.Message, set: [inserted_at: DateTime.utc_now()])

      {third, true} = Chat.list_messages_page(room, nil, 2)
      {second, true} = Chat.list_messages_page(room, hd(third), 2)
      {first, false} = Chat.list_messages_page(room, hd(second), 2)

      assert Enum.map(first ++ second ++ third, & &1.body) == ~w(m1 m2 m3 m4 m5)
    end

    test "only returns the room's messages", %{scope: scope, room: room} do
      message_fixture(scope, unique_room(), %{"body" => "elsewhere"})
      assert {page, false} = Chat.list_messages_page(room, nil, 10)
      refute "elsewhere" in Enum.map(page, & &1.body)
    end
  end

  describe "list_active_rooms/1" do
    test "lists rooms with messages, most recently active first", %{scope: scope} do
      [quiet, busy] = [unique_room(), unique_room()]
      message_fixture(scope, busy, %{"body" => "first"})
      message_fixture(scope, quiet, %{"body" => "second"})
      %{inserted_at: last_at} = message_fixture(scope, busy, %{"body" => "third"})

      assert [%{name: ^busy, last_message_at: ^last_at}, %{name: ^quiet}] =
               Chat.list_active_rooms()
    end

    test "breaks timestamp ties by the latest message", %{scope: scope} do
      [first, second] = [unique_room(), unique_room()]
      message_fixture(scope, first)
      message_fixture(scope, second)

      # Clock resolution can give consecutive messages the same timestamp.
      Repo.update_all(HoloChat.Chat.Message, set: [inserted_at: DateTime.utc_now()])

      assert [%{name: ^second}, %{name: ^first}] = Chat.list_active_rooms()
    end

    test "is capped at the limit", %{scope: scope} do
      for _ <- 1..3, do: message_fixture(scope, unique_room())
      assert length(Chat.list_active_rooms(2)) == 2
    end
  end

  describe "player_activity/2" do
    test "counts players and their messages since the last scenario started" do
      room = unique_room()
      gm = user_scope_fixture()
      [ada, bob] = [user_scope_fixture(), user_scope_fixture()]
      scenario = scenario_fixture(gm)

      message_fixture(bob, room)
      {:ok, _} = Chat.create_scenario_message(gm, room, scenario.id, scenario.title)
      for _ <- 1..3, do: message_fixture(ada, room)
      message_fixture(gm, room)
      {:ok, _} = Chat.create_assistant_message(room, "Holo", "AI replies don't count")
      {:ok, last} = Chat.create_character_message(room, "Neelix", "Neither do these", nil)

      since = DateTime.add(DateTime.utc_now(), -7, :day)

      assert %{^room => %{players: 2, messages: 4, last_message_at: last_at}} =
               Chat.player_activity([room], since)

      assert last_at == last.inserted_at
    end

    test "leaves out messages before `since`; rooms without messages get zeros" do
      room = unique_room()
      message_fixture(user_scope_fixture(), room)
      empty = unique_room()

      later = DateTime.add(DateTime.utc_now(), 1, :hour)

      assert %{
               ^room => %{players: 0, messages: 0, last_message_at: %DateTime{}},
               ^empty => %{players: 0, messages: 0, last_message_at: nil}
             } = Chat.player_activity([room, empty], later)
    end
  end

  describe "subscribe_rooms/0" do
    test "notifies about activity in any room, with the message", %{scope: scope, room: room} do
      Chat.subscribe_rooms()
      message = message_fixture(scope, room)

      assert_receive {:room_activity, %Message{room: ^room} = received}
      assert received.id == message.id
    end
  end

  describe "mentions?/2" do
    test "finds @name, ignoring case, outside words, e-mail addresses and code" do
      assert Chat.mentions?("hi @Ada!", "ada")
      assert Chat.mentions?("@ADA", "Ada")
      assert Chat.mentions?("ping @Will Riker, now", "Will Riker")

      refute Chat.mentions?("hi @Adam", "Ada")
      refute Chat.mentions?("mail ada@ada.org", "ada")
      refute Chat.mentions?("x@Ada", "Ada")
      refute Chat.mentions?("`@Ada` and\n```\n@Ada\n```", "Ada")
      refute Chat.mentions?("hi Ada", "Ada")
      refute Chat.mentions?(nil, "Ada")
    end
  end

  describe "unsubscribe/1" do
    test "stops messages from the room", %{scope: scope, room: room} do
      Chat.subscribe(room)
      Chat.unsubscribe(room)
      message_fixture(scope, room)

      refute_receive {:new_message, _}
    end
  end

  describe "valid_room?/1" do
    test "accepts slugs and rejects everything else" do
      assert Chat.valid_room?("lobby")
      assert Chat.valid_room?("elixir-2026")
      refute Chat.valid_room?("")
      refute Chat.valid_room?("-lobby")
      refute Chat.valid_room?("Lobby")
      refute Chat.valid_room?("has space")
      refute Chat.valid_room?(String.duplicate("a", 33))
    end
  end

  describe "room_used?/1" do
    test "is true once a room has messages, and always for the lobby",
         %{scope: scope, room: room} do
      refute Chat.room_used?(room)
      message_fixture(scope, room)
      assert Chat.room_used?(room)
      assert Chat.room_used?("lobby")
    end
  end

  describe "create_character_message/4" do
    test "stores and broadcasts a message written by a cast character",
         %{scope: scope, room: room} do
      %{id: id} = character_fixture(scope, %{"name" => "Luna"})
      Chat.subscribe(room)

      assert {:ok, %Message{from_assistant: true, character_id: ^id, username: "Luna"}} =
               Chat.create_character_message(room, "Luna", "Hello.", id)

      assert_receive {:new_message, %Message{character_id: ^id, body: "Hello."}}
    end
  end

  describe "create_message/4" do
    test "records the character a player wears", %{scope: scope, room: room} do
      %{id: id} = character_fixture(scope)

      assert {:ok, %Message{character_id: ^id, from_assistant: false} = message} =
               Chat.create_message(scope, room, %{"body" => "In costume."}, character_id: id)

      assert message.user_id == scope.user.id
    end
  end

  describe "create_scenario_message/4" do
    test "announces a scenario change in the room, by the scope's user",
         %{scope: scope, room: room} do
      %{id: id} = scenario_fixture(scope, %{"title" => "Risa"})
      Chat.subscribe(room)

      assert {:ok, %Message{kind: "scenario", scenario_id: ^id, body: "Risa"} = message} =
               Chat.create_scenario_message(scope, room, id, "Risa")

      assert message.user_id == scope.user.id
      assert_receive {:new_message, %Message{kind: "scenario", scenario_id: ^id}}
    end

    test "requires an account", %{room: room} do
      assert {:error, :unauthorized} = Chat.create_scenario_message(nil, room, 1, "Risa")
    end
  end

  describe "create_scenario_end_message/2" do
    test "announces that the scenario has ended", %{scope: scope, room: room} do
      Chat.subscribe(room)

      assert {:ok, %Message{kind: "scenario_end", scenario_id: nil} = message} =
               Chat.create_scenario_end_message(scope, room)

      assert message.user_id == scope.user.id
      assert_receive {:new_message, %Message{kind: "scenario_end"}}
    end

    test "requires an account", %{room: room} do
      assert {:error, :unauthorized} = Chat.create_scenario_end_message(nil, room)
    end
  end

  test "ordinary messages are chat messages", %{scope: scope, room: room} do
    assert %Message{kind: "chat", scenario_id: nil} = message_fixture(scope, room)
  end

  describe "delete_message/1" do
    test "deletes the message and announces it in its room" do
      room = unique_room()
      message = message_fixture(user_scope_fixture(), room)
      Chat.subscribe(room)

      assert {:ok, %Message{id: id}} = Chat.delete_message(message)

      assert id == message.id
      assert_receive {:message_deleted, %Message{id: ^id}}
      assert Chat.get_message(id) == nil
      assert Chat.list_recent_messages(room) == []
    end
  end

  describe "get_message/1" do
    test "gets a message by id, or nil" do
      message = message_fixture(user_scope_fixture(), unique_room())

      assert %Message{} = Chat.get_message("#{message.id}")
      assert Chat.get_message(-1) == nil
      assert Chat.get_message("nope") == nil
    end
  end
end
