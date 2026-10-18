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
    admin = user_scope_fixture(admin)
    room = unique_room()
    Chat.subscribe(room)
    {:ok, holo} = Assistant.create_persona(admin, %{"name" => "Holo", "rooms" => [room]})

    %{admin: admin, member: user_scope_fixture(), room: room, holo: holo}
  end

  test "answers a mention in the persona's room", %{admin: admin, member: member, room: room} do
    enable(admin)
    start_server()

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

  test "ignores messages that don't mention a persona",
       %{admin: admin, member: member, room: room} do
    enable(admin)
    start_server()

    message_fixture(member, room, %{"body" => "Holo is a nice name"})

    refute_receive {:new_message, %{from_assistant: true}}, 200
  end

  test "answers only in the persona's rooms", %{admin: admin, member: member} do
    enable(admin)
    start_server()
    elsewhere = unique_room()
    Chat.subscribe(elsewhere)

    message_fixture(member, elsewhere, %{"body" => "@Holo are you here?"})

    refute_receive {:new_message, %{from_assistant: true}}, 200
  end

  test "ignores assistant messages", %{admin: admin, room: room} do
    enable(admin)
    start_server()

    {:ok, _} = Chat.create_assistant_message(room, "Sage", "Talking about @Holo")

    assert_receive {:new_message, %{from_assistant: true, body: "Talking" <> _}}
    refute_receive {:new_message, %{from_assistant: true}}, 200
  end

  test "stays quiet while disabled", %{member: member, room: room} do
    start_server()

    message_fixture(member, room, %{"body" => "@Holo hello?"})

    refute_receive {:new_message, %{from_assistant: true}}, 200
  end

  test "each persona answers to its own name with its own prompt",
       %{admin: admin, member: member, room: room} do
    {:ok, _} =
      Assistant.create_persona(admin, %{
        "name" => "Sage",
        "rooms" => [room],
        "system_prompt" => "You are {name}, a code reviewer."
      })

    enable(admin)
    start_server()

    expect(LLMMock, :chat, fn _url, [system | _], _opts ->
      assert system.content == "You are Sage, a code reviewer."
      {:ok, "LGTM"}
    end)

    message_fixture(member, room, %{"body" => "@sage please review"})

    assert_receive {:new_message, %{from_assistant: true, username: "Sage", body: "LGTM"}}, 1000
  end

  test "answers mentions one at a time across personas, in order",
       %{admin: admin, member: member, room: room} do
    {:ok, _} = Assistant.create_persona(admin, %{"name" => "Sage", "rooms" => [room]})
    enable(admin)
    start_server()
    test = self()

    # Each generation blocks until the test releases it.
    expect(LLMMock, :chat, 3, fn _url, messages, _opts ->
      send(test, {:generating, self()})

      receive do
        :continue -> {:ok, "re: " <> List.last(messages).content}
      end
    end)

    name = member.user.username
    message_fixture(member, room, %{"body" => "@Holo and @Sage, hi"})
    message_fixture(member, room, %{"body" => "@Holo again"})

    replies =
      for _ <- 1..3 do
        assert_receive {:generating, generation}, 1000
        # No second generation starts while this one runs.
        refute_receive {:generating, _}, 100
        send(generation, :continue)

        assert_receive {:new_message, %{from_assistant: true, username: persona, body: body}},
                       1000

        {persona, body}
      end

    assert [{"Holo", _}, {"Sage", _}, {"Holo", last}] = replies
    assert last == "re: #{name}: @Holo again"
  end

  test "sends recent history up to the mention as context",
       %{admin: admin, member: member, room: room, holo: holo} do
    {:ok, _} = Assistant.update_persona(admin, holo, %{"context_messages" => "3"})
    enable(admin)
    for n <- 1..4, do: message_fixture(member, room, %{"body" => "earlier #{n}"})
    start_server()

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

  @tag :capture_log
  test "apologizes when the model can't be reached", %{admin: admin, member: member, room: room} do
    enable(admin)
    start_server()
    expect(LLMMock, :chat, fn _url, _messages, _opts -> {:error, :econnrefused} end)

    message_fixture(member, room, %{"body" => "@Holo hi"})

    assert_receive {:new_message, %{from_assistant: true, body: "Sorry" <> _}}, 1000
  end

  test "announces when a persona is typing", %{admin: admin, member: member, room: room} do
    enable(admin)
    Assistant.subscribe()
    start_server()
    expect(LLMMock, :chat, fn _url, _messages, _opts -> {:ok, "Hi"} end)

    assert_receive {:assistant_status, %{room: ^room, name: "Holo", online: true, typing: false}}

    message_fixture(member, room, %{"body" => "@Holo hi"})

    assert_receive {:assistant_status, %{room: ^room, name: "Holo", typing: true}}, 1000
    assert_receive {:assistant_status, %{room: ^room, name: "Holo", typing: false}}, 1000
  end

  test "follows persona changes", %{admin: admin, member: member, room: room, holo: holo} do
    enable(admin)
    Assistant.subscribe()
    start_server()
    assert_receive {:assistant_status, %{room: ^room, name: "Holo", online: true}}

    new_room = unique_room()
    Chat.subscribe(new_room)
    {:ok, _} = Assistant.update_persona(admin, holo, %{"name" => "Kobold", "rooms" => [new_room]})

    assert_receive {:assistant_status, %{room: ^room, name: "Holo", online: false}}, 1000
    assert_receive {:assistant_status, %{room: ^new_room, name: "Kobold", online: true}}, 1000

    expect(LLMMock, :chat, fn _url, _messages, _opts -> {:ok, "Present!"} end)
    message_fixture(member, new_room, %{"body" => "@kobold roll call"})

    assert_receive {:new_message, %{from_assistant: true, username: "Kobold", body: "Present!"}},
                   1000
  end

  test "goes offline everywhere when disabled", %{admin: admin, room: room} do
    enable(admin)
    Assistant.subscribe()
    start_server()
    assert_receive {:assistant_status, %{room: ^room, online: true}}

    {:ok, _} = Assistant.update_settings(admin, %{"enabled" => "false"})

    assert_receive {:assistant_status, %{room: ^room, name: "Holo", online: false}}, 1000
  end

  defp enable(admin) do
    {:ok, _} = Assistant.update_settings(admin, %{"enabled" => "true"})
  end

  defp start_server do
    start_supervised!({Server, name: nil})
  end
end
