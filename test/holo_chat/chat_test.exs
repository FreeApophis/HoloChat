defmodule HoloChat.ChatTest do
  use HoloChat.DataCase, async: true

  alias HoloChat.Chat
  alias HoloChat.Chat.Message

  describe "create_message/2" do
    test "stores the message and broadcasts it to the room" do
      Chat.subscribe("lobby")

      assert {:ok, %Message{} = message} =
               Chat.create_message("lobby", %{"username" => " ada ", "body" => " hello "})

      assert message.room == "lobby"
      assert message.username == "ada"
      assert message.body == "hello"
      assert_receive {:new_message, ^message}
    end

    test "does not broadcast to other rooms" do
      Chat.subscribe("other")
      {:ok, _} = Chat.create_message("lobby", %{"username" => "ada", "body" => "hi"})
      refute_receive {:new_message, _}
    end

    test "requires a username and a non-blank body" do
      assert {:error, changeset} =
               Chat.create_message("lobby", %{"username" => "", "body" => "   "})

      assert %{username: ["can't be blank"], body: ["can't be blank"]} = errors_on(changeset)
    end

    test "ignores a room passed in params" do
      {:ok, message} =
        Chat.create_message("lobby", %{"username" => "ada", "body" => "hi", "room" => "secret"})

      assert message.room == "lobby"
    end
  end

  describe "list_recent_messages/2" do
    test "returns only the room's messages, oldest first, capped at the limit" do
      for n <- 1..3, do: Chat.create_message("lobby", %{"username" => "ada", "body" => "m#{n}"})
      Chat.create_message("other", %{"username" => "bob", "body" => "elsewhere"})

      assert ["m2", "m3"] == Enum.map(Chat.list_recent_messages("lobby", 2), & &1.body)
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
