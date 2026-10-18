defmodule HoloChatWeb.ChatLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HoloChat.Chat

  test "shows the lobby with its history", %{conn: conn} do
    {:ok, message} = Chat.create_message("lobby", %{"username" => "ada", "body" => "earlier"})

    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#room-title", "lobby")
    assert has_element?(view, "#messages-#{message.id}", "earlier")
  end

  test "sending a message shows it and clears the body but keeps the name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#message-form", message: %{username: "ada", body: "hello there"})
    |> render_submit()

    assert has_element?(
             view,
             "#messages > div[id^='messages-']:not(#messages-empty)",
             "hello there"
           )

    assert has_element?(view, "#message-form input[name='message[username]'][value='ada']")
    refute has_element?(view, "#message-form input[name='message[body]'][value]")
  end

  test "messages from other clients appear live", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rooms/elixir")
    {:ok, other, _html} = live(build_conn(), ~p"/rooms/elixir")

    other
    |> form("#message-form", message: %{username: "bob", body: "from bob"})
    |> render_submit()

    assert has_element?(view, "#messages > div[id^='messages-']:not(#messages-empty)", "from bob")
  end

  test "messages stay in their room", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rooms/elixir")
    Chat.create_message("lobby", %{"username" => "bob", "body" => "lobby only"})

    refute has_element?(
             view,
             "#messages > div[id^='messages-']:not(#messages-empty)",
             "lobby only"
           )
  end

  test "an invalid message shows errors and is not sent", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#message-form", message: %{username: "", body: "hi"})
    |> render_submit()

    refute has_element?(view, "#messages > div[id^='messages-']:not(#messages-empty)")
    assert Chat.list_recent_messages("lobby") == []
  end

  test "switching rooms normalizes the name", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    view
    |> form("#room-form", room: %{name: "#Elixir Fans!"})
    |> render_submit()

    assert_redirect(view, ~p"/rooms/elixir-fans")
  end

  test "an invalid room in the URL redirects to the lobby", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/"}}} = live(conn, ~p"/rooms/Not_Valid")
  end
end
