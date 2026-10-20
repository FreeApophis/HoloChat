defmodule HoloChatWeb.ChatTopicTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures

  alias HoloChat.Rooms

  defp as(scope), do: build_conn_with_unique_ip() |> log_in_user(scope.user)

  defp set_topic(view, topic) do
    view |> element("#edit-topic") |> render_click()
    view |> form("#topic-form", topic: %{topic: topic}) |> render_submit()
  end

  test "game masters set the topic, and everyone in the room sees it", %{conn: conn} do
    gm = user_scope_fixture()
    room = unique_room()
    {:ok, _} = Rooms.post_message(gm, room, %{"body" => "My room now"})
    {:ok, watcher, _html} = live(conn, ~p"/rooms/#{room}")
    {:ok, view, _html} = live(as(gm), ~p"/rooms/#{room}")

    set_topic(view, "Talk about **jazz**, see #lobby")

    for v <- [view, watcher] do
      assert has_element?(v, "#room-topic strong", "jazz")
      assert has_element?(v, "#room-topic a[href='/rooms/lobby']")
    end

    refute has_element?(view, "#topic-form")

    {:ok, list, _html} = live(build_conn_with_unique_ip(), ~p"/rooms")
    assert has_element?(list, "#channel-#{room} [data-role='topic'] strong", "jazz")
  end

  test "moderators set the lobby's topic; players can't change topics", %{conn: conn} do
    {:ok, player_view, _html} = live(conn |> log_in_user(user_fixture()), ~p"/rooms/lobby")
    refute has_element?(player_view, "#edit-topic")

    {:ok, view, _html} = live(as(role_scope_fixture(:moderator)), ~p"/rooms/lobby")
    set_topic(view, "Welcome, everyone!")

    assert has_element?(view, "#room-topic", "Welcome, everyone!")
  end

  test "clearing the topic removes it" do
    moderator = role_scope_fixture(:moderator)
    room = unique_room()
    {:ok, _} = Rooms.set_topic(moderator, room, "Old news")
    {:ok, view, _html} = live(as(moderator), ~p"/rooms/#{room}")
    assert has_element?(view, "#room-topic", "Old news")

    set_topic(view, "  ")

    refute has_element?(view, "#room-topic")
  end

  test "a scene shows its scenario's topic until the room has its own", %{conn: conn} do
    gm = user_scope_fixture()
    scene = roleplay_room_fixture(gm, %{"topic" => "Sun and surf."})
    {:ok, view, _html} = live(conn, ~p"/rooms/#{scene.name}")
    assert has_element?(view, "#room-topic", "Sun and surf.")

    {:ok, _} = Rooms.set_topic(gm, scene.name, "Tonight: the beach party")

    assert has_element?(view, "#room-topic", "Tonight: the beach party")
    refute has_element?(view, "#room-topic", "Sun and surf.")
  end
end
