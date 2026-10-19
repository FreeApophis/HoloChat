defmodule HoloChatWeb.ChannelMasterTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures
  import HoloChat.ScenariosFixtures

  setup %{conn: conn} do
    creator = user_fixture()
    %{conn: log_in_user(conn, creator), creator: creator, name: unique_room()}
  end

  defp say(view, body) do
    view |> form("#message-form", message: %{body: body}) |> render_submit()
  end

  describe "the creator of a channel" do
    test "becomes its game master and can start a scenario there",
         %{conn: conn, creator: creator, name: name} do
      scenario = scenario_fixture(user_scope_fixture(creator), %{"title" => "Risa"})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{name}")
      refute has_element?(view, "#start-scene-link")

      say(view, "Welcome to my channel")

      assert has_element?(view, "#start-scene-link[href='/scenarios?room=#{name}']")

      {:ok, library, _html} = live(conn, ~p"/scenarios?room=#{name}")

      {:ok, view, _html} =
        library
        |> element("#play-scenario-#{scenario.id}")
        |> render_click()
        |> follow_redirect(conn, ~p"/rooms/#{name}")

      assert has_element?(view, "#scene-title", "Risa")
      assert has_element?(view, "#scene-settings-link")
    end

    test "is the only one offered to start a scenario", %{conn: conn, name: name} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{name}")
      say(view, "First!")

      other = build_conn_with_unique_ip() |> log_in_user(user_fixture())
      {:ok, other_view, _html} = live(other, ~p"/rooms/#{name}")
      say(other_view, "Second")

      refute has_element?(other_view, "#start-scene-link")
    end
  end

  test "nobody becomes game master of the lobby", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/rooms/lobby")
    say(view, "Hi all")

    refute has_element?(view, "#start-scene-link")
  end

  test "game masters can start a new scenario after the last one ended",
       %{conn: conn, creator: creator} do
    gm = user_scope_fixture(creator)
    room = roleplay_room_fixture(gm)
    {:ok, _room} = HoloChat.Rooms.end_scenario(gm, room)

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")

    assert has_element?(view, "#start-scene-link[href='/scenarios?room=#{room.name}']")
  end

  test "chat rooms from before channels had creators stay with the admins",
       %{conn: conn, name: name} do
    message_fixture(user_scope_fixture(), name)
    {:ok, view, _html} = live(conn, ~p"/rooms/#{name}")
    say(view, "Hello")

    refute has_element?(view, "#start-scene-link")
  end
end
