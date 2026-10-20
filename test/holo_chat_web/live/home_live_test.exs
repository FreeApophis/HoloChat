defmodule HoloChatWeb.HomeLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.NewsFixtures
  import HoloChat.RoomsFixtures

  alias HoloChat.Rooms

  describe "as a guest" do
    test "the main page is a landing page, not the lobby", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#landing-hero")
      refute has_element?(view, "#room-list")
      refute has_element?(view, "#messages")
    end

    test "invites guests to sign up or look around the lobby", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#landing-signup[href='/users/register']")
      assert has_element?(view, "#landing-enter[href='/rooms/lobby']")
    end

    test "the lobby link opens the lobby", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      {:ok, lobby, _html} =
        view
        |> element("#landing-enter")
        |> render_click()
        |> follow_redirect(conn, ~p"/rooms/lobby")

      assert has_element?(lobby, "#room-title", "lobby")
    end
  end

  describe "as a user" do
    setup :register_and_log_in_user

    test "offers the lobby and scenes instead of sign-up", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#landing-enter[href='/rooms/lobby']")
      assert has_element?(view, "#landing-roleplay[href='/scenarios']")
      refute has_element?(view, "#landing-signup")
    end
  end

  describe "news" do
    test "shows the two latest posts above the destinations", %{conn: conn} do
      editor = role_scope_fixture(:news_editor)
      oldest = published_post_fixture(editor, %{"title" => "Oldest"}, ~U[2026-10-01 10:00:00Z])
      middle = published_post_fixture(editor, %{"title" => "Middle"}, ~U[2026-10-02 10:00:00Z])
      newest = published_post_fixture(editor, %{"title" => "Newest"}, ~U[2026-10-03 10:00:00Z])
      _draft = post_fixture(editor, %{"title" => "Draft"})

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#landing-news #news-#{newest.id}", "Newest")
      assert has_element?(view, "#landing-news #news-#{middle.id}", "Middle")
      refute has_element?(view, "#news-#{oldest.id}")
      assert has_element?(view, "#landing-all-news[href='/news']")

      assert section_ids(view) |> Enum.take(3) == [
               "landing-hero",
               "landing-news",
               "landing-destinations"
             ]
    end

    test "is left out while there is no news", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      refute has_element?(view, "#landing-news")
    end
  end

  describe "destinations" do
    setup do
      %{gm: user_scope_fixture()}
    end

    test "are the rooms of the two scenarios with the most players this week",
         %{conn: conn, gm: gm} do
      busy = roleplay_room_fixture(gm, %{"title" => "Risa"})
      quieter = roleplay_room_fixture(gm, %{"title" => "Eldermere"})
      idle = roleplay_room_fixture(gm, %{"title" => "Deep Station"})

      for _ <- 1..3, do: say(user_scope_fixture(), busy.name)
      say(user_scope_fixture(), quieter.name)
      # One very chatty player doesn't make a room popular.
      chatty = user_scope_fixture()
      for _ <- 1..5, do: say(chatty, idle.name)
      say(user_scope_fixture(), quieter.name)

      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#destination-#{busy.name}", "Risa")
      assert has_element?(view, "#destination-#{busy.name}", "3 players this week")
      assert has_element?(view, "#destination-#{quieter.name}", "Eldermere")
      refute has_element?(view, "#destination-#{idle.name}")
      assert destination_ids(view) == ["destination-#{busy.name}", "destination-#{quieter.name}"]

      assert {:error, {:live_redirect, %{to: to}}} =
               view |> element("#destination-#{busy.name} a") |> render_click()

      assert to == "/rooms/#{busy.name}"
    end

    test "show one room per scenario", %{conn: conn, gm: gm} do
      first = roleplay_room_fixture(gm, %{"title" => "Risa"})
      second = roleplay_room_fixture(gm, %{"scenario_id" => first.scenario_id})
      other = roleplay_room_fixture(gm, %{"title" => "Eldermere"})
      for _ <- 1..2, do: say(user_scope_fixture(), first.name)
      for _ <- 1..2, do: say(user_scope_fixture(), second.name)
      say(user_scope_fixture(), other.name)

      {:ok, view, _html} = live(conn, ~p"/")

      assert length(destination_ids(view)) == 2
      assert has_element?(view, "#destination-#{other.name}")
    end

    test "are topped up with recently active rooms in a quiet week", %{conn: conn, gm: gm} do
      played = roleplay_room_fixture(gm, %{"title" => "Risa"})
      waiting = roleplay_room_fixture(gm, %{"title" => "Eldermere"})
      say(user_scope_fixture(), played.name)

      {:ok, view, _html} = live(conn, ~p"/")

      assert destination_ids(view) == [
               "destination-#{played.name}",
               "destination-#{waiting.name}"
             ]

      assert has_element?(view, "#destination-#{waiting.name}", "Waiting for players")
    end

    test "invite to the scenarios when no room plays one", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#no-destinations a[href='/scenarios']")
    end
  end

  defp say(scope, room_name) do
    {:ok, _message} = Rooms.post_message(scope, room_name, %{"body" => "Hello"})
  end

  defp destination_ids(view), do: ids(view, "#destinations > article")
  defp section_ids(view), do: ids(view, "#landing > section")

  defp ids(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("id")
  end

  test "the header links to the lobby from every page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/characters")

    assert has_element?(view, "#lobby-nav-link[href='/rooms/lobby']")
  end
end
