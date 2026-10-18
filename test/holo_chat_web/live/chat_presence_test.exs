defmodule HoloChatWeb.ChatPresenceTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures
  import HoloChatWeb.PresenceHelpers

  alias HoloChatWeb.Presence

  setup do
    # PubSub and Presence are global, so each test gets its own room.
    room = unique_room()
    Presence.subscribe(room)

    on_exit(&await_presence_fetchers/0)

    %{room: room}
  end

  test "lists members by name and counts guests", %{room: room} do
    {ada, _view} = join_as_user(room)
    guest = join_as_guest(room)

    assert has_element?(guest, "#online-count", "2 online")
    assert has_element?(guest, "#online-users[title='#{ada.username}, 1 guest']")
  end

  test "shows others typing, but not yourself", %{room: room} do
    {ada, ada_view} = join_as_user(room)
    {_bob, bob_view} = join_as_user(room)

    type(ada_view, "hel")
    await_presence(%{name: ada.username, typing: true})

    assert has_element?(bob_view, "#typing-indicator", "#{ada.username} is typing")
    refute has_element?(ada_view, "#typing-indicator", "is typing")
  end

  test "typing stops when the message is sent", %{room: room} do
    {ada, ada_view} = join_as_user(room)
    guest = join_as_guest(room)

    type(ada_view, "hello")
    await_presence(%{name: ada.username, typing: true})

    ada_view
    |> form("#message-form", message: %{body: "hello"})
    |> render_submit()

    await_presence(%{name: ada.username, typing: false})
    refute has_element?(guest, "#typing-indicator", "is typing")
  end

  test "typing stops when the body is cleared", %{room: room} do
    {ada, ada_view} = join_as_user(room)
    guest = join_as_guest(room)

    type(ada_view, "hello")
    await_presence(%{name: ada.username, typing: true})
    type(ada_view, "")
    await_presence(%{name: ada.username, typing: false})

    refute has_element?(guest, "#typing-indicator", "is typing")
  end

  test "typing stops after the idle timeout", %{room: room} do
    {ada, ada_view} = join_as_user(room)
    guest = join_as_guest(room)

    type(ada_view, "hello")
    await_presence(%{name: ada.username, typing: true})

    # Simulate the timer firing instead of waiting for it.
    send(ada_view.pid, :typing_timeout)
    await_presence(%{name: ada.username, typing: false})

    refute has_element?(guest, "#typing-indicator", "is typing")
  end

  test "several typists are summarized", %{room: room} do
    typists = for _ <- 1..3, do: join_as_user(room)
    watcher = join_as_guest(room)

    for {user, view} <- typists do
      type(view, "hi")
      await_presence(%{name: user.username, typing: true})
    end

    assert has_element?(watcher, "#typing-indicator", "Several people are typing")
  end

  defp join_as_user(room) do
    user = user_fixture()

    {:ok, view, _html} =
      build_conn_with_unique_ip() |> log_in_user(user) |> live(~p"/rooms/#{room}")

    {user, view}
  end

  defp join_as_guest(room) do
    {:ok, view, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{room}")
    view
  end

  defp type(view, body) do
    view
    |> form("#message-form", message: %{body: body})
    |> render_change()
  end
end
