defmodule HoloChatWeb.RoleplayLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.{Accounts, Rooms, Scenarios}

  describe "scenes in the scenario library" do
    test "the sparkle icon leads to the scenario library", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/rooms/lobby")
      assert has_element?(view, "#roleplay-nav-link[href='/scenarios']")
    end

    test "scenario cards list the rooms playing them, but not chat rooms", %{conn: conn} do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm, %{"title" => "The Sunken Keep"})
      chat_room = unique_room()
      message_fixture(gm, chat_room)

      {:ok, view, _html} = live(conn, ~p"/scenarios")

      card = "#scenario-#{room.scenario_id}"
      assert has_element?(view, card, "The Sunken Keep")
      assert has_element?(view, "#{card} a#scene-room-#{room.name}[href='/rooms/#{room.name}']")
      refute has_element?(view, "#scene-room-#{chat_room}")
    end

    test "rooms playing the same scenario share its card", %{conn: conn} do
      gm = user_scope_fixture()
      first = roleplay_room_fixture(gm, %{"title" => "Twin Halls"})
      second = roleplay_room_fixture(gm, %{"scenario_id" => first.scenario_id})
      other = roleplay_room_fixture(gm)

      {:ok, view, _html} = live(conn, ~p"/scenarios")

      card = "#scenario-#{first.scenario_id}"
      assert has_element?(view, "#{card} #scene-room-#{first.name}")
      assert has_element?(view, "#{card} #scene-room-#{second.name}")
      refute has_element?(view, "#{card} #scene-room-#{other.name}")
      assert has_element?(view, "#scenario-#{other.scenario_id} #scene-room-#{other.name}")
    end

    test "the old role-play pages are gone", %{conn: conn} do
      for path <- ["/roleplay", "/roleplay/new"] do
        assert get(conn, path).status == 404
      end
    end
  end

  describe "creating a scene" do
    setup :register_and_log_in_user

    setup %{user: user} do
      %{scenario: scenario_fixture(user_scope_fixture(user), %{"title" => "Moonlit Market"})}
    end

    test "opens a scene in a new channel from a scenario card",
         %{conn: conn, scenario: scenario} do
      name = unique_room()

      {:ok, view, _html} =
        conn
        |> open_scene_form(scenario)
        |> form("#new-scene-form-#{scenario.id}", scene: %{name: name})
        |> render_submit()
        |> follow_redirect(conn, ~p"/rooms/#{name}")

      assert has_element?(view, "#scene-title", "Moonlit Market")
      assert has_element?(view, "#scene-settings-link")

      {:ok, library, _html} = live(conn, ~p"/scenarios")
      assert has_element?(library, "#scenario-#{scenario.id} #scene-room-#{name}")
    end

    test "refuses a channel already used by a chat room",
         %{conn: conn, user: user, scenario: scenario} do
      name = unique_room()
      message_fixture(user_scope_fixture(user), name)

      html =
        conn
        |> open_scene_form(scenario)
        |> form("#new-scene-form-#{scenario.id}", scene: %{name: name})
        |> render_submit()

      assert html =~ "is already taken"
    end

    test "refuses a channel run by other game masters", %{conn: conn, scenario: scenario} do
      room = roleplay_room_fixture(user_scope_fixture())

      html =
        conn
        |> open_scene_form(scenario)
        |> form("#new-scene-form-#{scenario.id}", scene: %{name: room.name})
        |> render_submit()

      assert html =~ "has other game masters"
      assert Rooms.get_room(room.name).scenario_id == room.scenario_id
    end
  end

  describe "a role-play room" do
    setup do
      gm = user_scope_fixture()

      room =
        roleplay_room_fixture(gm, %{
          "title" => "The Inn",
          "description" => "A storm traps everyone."
        })

      %{gm: gm, room: room}
    end

    test "shows its scene to everyone", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")

      assert has_element?(view, "#scene-title", "The Inn")
      refute has_element?(view, "#scene-settings-link")

      view |> element("#show-scenario") |> render_click()
      assert has_element?(view, "#scenario", "A storm traps everyone.")
    end

    test "shows its scenario's background image", %{conn: conn, gm: gm, room: room} do
      {:ok, scenario} =
        Scenarios.update_scenario_image(
          gm,
          Scenarios.get_scenario(room.scenario_id),
          :background,
          image_binary(32, 18, {4, 5, 6})
        )

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")

      assert has_element?(
               view,
               "#scene-background[style*='/avatars/#{scenario.background_image_id}']"
             )
    end

    test "marks role-play rooms in the room list", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")
      assert has_element?(view, "#room-link-#{room.name}[data-kind='roleplay']")
    end
  end

  defp gm_user(scope), do: scope.user

  # Clicks "New scene" on the scenario's card, which asks for the channel.
  defp open_scene_form(conn, scenario) do
    {:ok, view, _html} = live(conn, ~p"/scenarios")
    view |> element("#play-scenario-#{scenario.id}") |> render_click()
    view
  end

  describe "scene settings" do
    setup %{conn: conn} do
      gm_user = user_fixture()
      gm = user_scope_fixture(gm_user)
      room = roleplay_room_fixture(gm)
      %{conn: log_in_user(conn, gm_user), gm: gm, room: room}
    end

    test "show the current scenario and let its owner edit it", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

      assert has_element?(view, "#current-scenario", "A Scenario")

      assert has_element?(
               view,
               "#edit-scenario-link[href='/scenarios/#{room.scenario_id}/edit']"
             )
    end

    test "offer the scenario editor only to its owner", %{gm: gm} do
      someone_elses = scenario_fixture(user_scope_fixture())
      room = roleplay_room_fixture(gm, %{"scenario_id" => someone_elses.id})
      conn = build_conn_with_unique_ip() |> log_in_user(gm_user(gm))

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

      refute has_element?(view, "#edit-scenario-link")
    end

    test "let a game master add and remove co-game masters", %{conn: conn, room: room} do
      other = user_fixture()
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

      view
      |> form("#add-master-form", master: %{username: other.username})
      |> render_submit()

      assert has_element?(view, "#master-#{other.id}")
      assert Rooms.game_master?(user_scope_fixture(other), Rooms.get_room(room.name))

      view |> element("#remove-master-#{other.id}") |> render_click()
      refute has_element?(view, "#master-#{other.id}")
    end

    test "report unknown usernames", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

      html =
        view
        |> form("#add-master-form", master: %{username: "nobody-#{unique_username()}"})
        |> render_submit()

      assert html =~ "No user with that name"
    end

    test "are closed to players", %{room: room} do
      conn = build_conn_with_unique_ip() |> log_in_user(user_fixture())

      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/rooms/#{room.name}/settings")
      assert path == ~p"/rooms/#{room.name}"
    end

    test "are open to admins", %{room: room} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      conn = build_conn_with_unique_ip() |> log_in_user(admin)

      assert {:ok, _view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")
    end
  end
end
