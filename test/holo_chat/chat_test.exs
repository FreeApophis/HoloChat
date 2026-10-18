defmodule HoloChat.ChatTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures

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

  describe "list_recent_messages/2" do
    test "returns only the room's messages, oldest first, capped at the limit",
         %{scope: scope, room: room} do
      for n <- 1..3, do: message_fixture(scope, room, %{"body" => "m#{n}"})
      message_fixture(scope, unique_room(), %{"body" => "elsewhere"})

      assert ["m2", "m3"] == Enum.map(Chat.list_recent_messages(room, 2), & &1.body)
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
end
