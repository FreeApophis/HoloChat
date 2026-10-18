defmodule HoloChat.Assistant.ServerTest do
  # The server and its tasks touch the database and the LLM mock from their own
  # processes, started before the test could allow them: use shared modes.
  use HoloChat.DataCase, async: false

  import Mox
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures

  alias HoloChat.{Accounts, Assistant, Chat}
  alias HoloChat.Assistant.{LLMMock, Server}

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
    room = unique_room()
    Chat.subscribe(room)

    %{admin: user_scope_fixture(admin), member: user_scope_fixture(), room: room}
  end

  test "answers a mention in its room", %{admin: admin, member: member, room: room} do
    enable(admin)
    start_server(room)

    expect(LLMMock, :chat, fn "http://localhost:5001", messages, opts ->
      assert %{role: "system"} = hd(messages)
      assert List.last(messages).content == "#{member.user.username}: @Holo hi"
      assert opts[:max_tokens] == 512
      {:ok, "<think>a greeting</think>Hello there!"}
    end)

    message_fixture(member, room, %{"body" => "@Holo hi"})

    assert_receive {:new_message,
                    %{from_assistant: true, username: "Holo", body: "Hello there!"}},
                   1000
  end

  test "ignores messages that don't mention it", %{admin: admin, member: member, room: room} do
    enable(admin)
    start_server(room)

    message_fixture(member, room, %{"body" => "Holo is a nice name"})

    refute_receive {:new_message, %{from_assistant: true}}, 200
  end

  test "ignores its own messages", %{admin: admin, room: room} do
    enable(admin)
    start_server(room)

    {:ok, _} = Chat.create_assistant_message(room, "Holo", "Talking about @Holo")

    assert_receive {:new_message, %{from_assistant: true, body: "Talking" <> _}}
    refute_receive {:new_message, %{from_assistant: true}}, 200
  end

  test "stays quiet while disabled", %{member: member, room: room} do
    start_server(room)

    message_fixture(member, room, %{"body" => "@Holo hello?"})

    refute_receive {:new_message, %{from_assistant: true}}, 200
  end

  test "sends recent history up to the mention as context",
       %{admin: admin, member: member, room: room} do
    enable(admin, %{"context_messages" => "3"})
    for n <- 1..4, do: message_fixture(member, room, %{"body" => "earlier #{n}"})
    start_server(room)

    expect(LLMMock, :chat, fn _url, messages, _opts ->
      assert Enum.map(tl(messages), & &1.content) ==
               Enum.map(
                 ["earlier 3", "earlier 4", "@Holo summarize"],
                 &"#{member.user.username}: #{&1}"
               )

      {:ok, "Done."}
    end)

    message_fixture(member, room, %{"body" => "@Holo summarize"})

    assert_receive {:new_message, %{from_assistant: true, body: "Done."}}, 1000
  end

  test "answers mentions one at a time, in order", %{admin: admin, member: member, room: room} do
    enable(admin)
    start_server(room)

    expect(LLMMock, :chat, 2, fn _url, messages, _opts ->
      {:ok, "re: " <> List.last(messages).content}
    end)

    message_fixture(member, room, %{"body" => "@Holo one"})
    message_fixture(member, room, %{"body" => "@Holo two"})

    name = member.user.username
    assert_receive {:new_message, %{from_assistant: true, body: "re: " <> first}}, 1000
    assert_receive {:new_message, %{from_assistant: true, body: "re: " <> second}}, 1000
    assert [first, second] == ["#{name}: @Holo one", "#{name}: @Holo two"]
  end

  @tag :capture_log
  test "apologizes when the model can't be reached", %{admin: admin, member: member, room: room} do
    enable(admin)
    start_server(room)
    expect(LLMMock, :chat, fn _url, _messages, _opts -> {:error, :econnrefused} end)

    message_fixture(member, room, %{"body" => "@Holo hi"})

    assert_receive {:new_message, %{from_assistant: true, body: "Sorry" <> _}}, 1000
  end

  test "announces when it is typing", %{admin: admin, member: member, room: room} do
    enable(admin)
    start_server(room)
    Assistant.subscribe()
    expect(LLMMock, :chat, fn _url, _messages, _opts -> {:ok, "Hi"} end)

    message_fixture(member, room, %{"body" => "@Holo hi"})

    assert_receive {:assistant_status, %{room: ^room, typing: true, online: true}}, 1000
    assert_receive {:assistant_status, %{room: ^room, typing: false, online: true}}, 1000
  end

  test "follows settings changes", %{admin: admin, member: member, room: room} do
    start_server(room)
    Assistant.subscribe()

    enable(admin, %{"name" => "Kobold"})
    assert_receive {:assistant_status, %{room: ^room, online: true, name: "Kobold"}}, 1000

    expect(LLMMock, :chat, fn _url, _messages, _opts -> {:ok, "Present!"} end)
    message_fixture(member, room, %{"body" => "@kobold roll call"})

    assert_receive {:new_message, %{from_assistant: true, username: "Kobold", body: "Present!"}},
                   1000
  end

  defp enable(admin, attrs \\ %{}) do
    {:ok, _} = Assistant.update_settings(admin, Map.merge(%{"enabled" => "true"}, attrs))
  end

  defp start_server(room) do
    start_supervised!({Server, room: room, name: nil})
  end
end
