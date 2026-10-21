defmodule HoloChatWeb.ChatRegenerateTest do
  # Runs the real assistant server, which needs the shared sandbox and Mox mode.
  use HoloChatWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures

  alias HoloChat.{Accounts, Assistant, Chat}
  alias HoloChat.Assistant.{LLMMock, Server}

  setup :set_mox_global
  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
    admin = user_scope_fixture(admin)
    {:ok, _} = Assistant.update_settings(admin, %{"enabled" => "true"})

    room = unique_room()
    {:ok, _} = Assistant.create_persona(admin, %{"name" => "Holo", "rooms" => [room]})
    start_supervised!({Server, name: nil})
    Chat.subscribe(room)

    user = user_fixture()
    conn = log_in_user(conn, user)

    %{conn: conn, room: room, user: user_scope_fixture(user)}
  end

  test "regenerates the latest reply in place, with sparkles while it works",
       %{conn: conn, room: room, user: user} do
    test = self()

    expect(LLMMock, :chat, fn _url, _messages, _opts -> {:ok, "A dull answer."} end)
    message_fixture(user, room, %{"body" => "@Holo tell me a story"})
    assert_receive {:new_message, %{from_assistant: true} = reply}, 1000

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")
    assert has_element?(view, "#regenerate-message-#{reply.id}")

    expect(LLMMock, :chat, fn _url, messages, _opts ->
      assert List.last(messages).content =~ "@Holo tell me a story"
      refute Enum.any?(messages, &(&1.content =~ "A dull answer."))
      send(test, {:generating, self()})

      receive do
        :continue -> {:ok, "Once upon a time, a dragon learned to knit."}
      end
    end)

    view |> element("#regenerate-message-#{reply.id}") |> render_click()

    assert_receive {:generating, llm}, 1000
    assert_receive {:message_regenerating, %{id: id}} when id == reply.id
    await_view(view)
    assert has_element?(view, "#messages-#{reply.id} [data-regenerating]")

    send(llm, :continue)
    assert_receive {:message_updated, %{id: ^id}}, 1000
    await_view(view)

    refute has_element?(view, "#messages-#{reply.id} [data-regenerating]")
    assert has_element?(view, "#messages-#{reply.id}", "a dragon learned to knit")
    refute has_element?(view, "#messages-#{reply.id}", "A dull answer.")
    assert [_question, %{body: "Once upon" <> _}] = Chat.list_recent_messages(room)
  end

  test "only the room's latest message can be regenerated, and only if the AI wrote it",
       %{conn: conn, room: room, user: user} do
    expect(LLMMock, :chat, fn _url, _messages, _opts -> {:ok, "Hi!"} end)
    message_fixture(user, room, %{"body" => "@Holo hi"})
    assert_receive {:new_message, %{from_assistant: true} = reply}, 1000
    later = message_fixture(user, room, %{"body" => "Thanks."})

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

    refute has_element?(view, "#regenerate-message-#{later.id}")

    render_click(view, "regenerate_message", %{"id" => reply.id})
    assert has_element?(view, "#flash-error", "can't regenerate")

    refute_receive {:message_regenerating, _}, 200
  end
end
