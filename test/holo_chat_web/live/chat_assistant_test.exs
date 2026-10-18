defmodule HoloChatWeb.ChatAssistantTest do
  # Runs the real assistant server, which needs the shared sandbox and Mox mode.
  use HoloChatWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures
  import HoloChatWeb.PresenceHelpers

  alias HoloChat.{Accounts, Assistant}
  alias HoloChat.Assistant.{LLMMock, Server}
  alias HoloChatWeb.Presence

  setup :set_mox_global
  setup :verify_on_exit!

  setup %{conn: conn} do
    {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
    {:ok, _} = Assistant.update_settings(user_scope_fixture(admin), %{"enabled" => "true"})

    room = unique_room()
    Presence.subscribe(room)
    on_exit(&await_presence_fetchers/0)
    start_supervised!({Server, room: room, name: nil})
    await_presence(%{name: "Holo"})

    user = user_fixture()
    {:ok, view, _html} = conn |> log_in_user(user) |> live(~p"/rooms/#{room}")

    %{view: view, room: room}
  end

  test "the assistant is listed as online", %{view: view} do
    assert has_element?(view, "#online-users[title*='Holo']")
  end

  test "shows the assistant typing, then its reply", %{view: view} do
    test = self()

    expect(LLMMock, :chat, fn _url, _messages, _opts ->
      send(test, {:generating, self()})

      receive do
        :continue -> {:ok, "Hello from the model!"}
      end
    end)

    view |> form("#message-form", message: %{body: "@Holo hi"}) |> render_submit()

    assert_receive {:generating, llm}, 1000
    await_presence(%{name: "Holo", typing: true})
    assert has_element?(view, "#typing-indicator", "Holo is typing")

    send(llm, :continue)
    await_presence(%{name: "Holo", typing: false})

    refute has_element?(view, "#typing-indicator", "is typing")
    assert has_element?(view, "#messages [data-role='assistant-badge']")
    assert render(view) =~ "Hello from the model!"
  end
end
