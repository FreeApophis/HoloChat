defmodule HoloChatWeb.RoleplayLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.{Accounts, Rooms, Scenarios}

  describe "the role-play overview" do
    test "shows role-play rooms as cards, but not chat rooms", %{conn: conn} do
      gm = user_scope_fixture()

      room =
        roleplay_room_fixture(gm, %{"title" => "The Sunken Keep", "topic" => "Water rises."})

      chat_room = unique_room()
      message_fixture(gm, chat_room)

      {:ok, view, _html} = live(conn, ~p"/roleplay")

      card = "#scenario-card-#{room.scenario_id}"
      assert has_element?(view, card, "The Sunken Keep")
      assert has_element?(view, card, "Water rises.")
      assert has_element?(view, "#{card} a#scene-room-#{room.name}[href='/rooms/#{room.name}']")
      refute has_element?(view, "#scene-room-#{chat_room}")
    end

    test "groups rooms playing the same scenario into one card", %{conn: conn} do
      gm = user_scope_fixture()
      first = roleplay_room_fixture(gm, %{"title" => "Twin Halls"})
      second = roleplay_room_fixture(gm, %{"scenario_id" => first.scenario_id})
      other = roleplay_room_fixture(gm)

      {:ok, view, _html} = live(conn, ~p"/roleplay")

      card = "#scenario-card-#{first.scenario_id}"
      assert has_element?(view, "#{card} #scene-room-#{first.name}")
      assert has_element?(view, "#{card} #scene-room-#{second.name}")
      refute has_element?(view, "#{card} #scene-room-#{other.name}")
      assert has_element?(view, "#scenario-card-#{other.scenario_id} #scene-room-#{other.name}")
    end

    test "shows the card image of the room's scenario", %{conn: conn} do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)

      {:ok, scenario} =
        Scenarios.update_scenario_image(
          gm,
          Scenarios.get_scenario(room.scenario_id),
          :card,
          image_binary(32, 18, {1, 2, 3})
        )

      {:ok, view, _html} = live(conn, ~p"/roleplay")

      assert has_element?(
               view,
               "#scenario-card-#{scenario.id} img[src='/avatars/#{scenario.card_image_id}']"
             )
    end

    test "offers guests no way to create a room", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/roleplay")
      refute has_element?(view, "#new-room-link")
    end
  end

  describe "creating a role-play room" do
    setup :register_and_log_in_user

    setup %{user: user} do
      %{scenario: scenario_fixture(user_scope_fixture(user), %{"title" => "Moonlit Market"})}
    end

    test "makes the creator its game master", %{conn: conn, scenario: scenario} do
      {:ok, view, _html} = live(conn, ~p"/roleplay")
      assert has_element?(view, "#new-room-link[href='/roleplay/new']")
      {:ok, view, _html} = live(conn, ~p"/roleplay/new")
      name = unique_room()

      {:ok, view, _html} =
        view
        |> form("#room-form", room: %{name: name, scenario_id: scenario.id})
        |> render_submit()
        |> follow_redirect(conn, ~p"/rooms/#{name}")

      assert has_element?(view, "#scene-title", "Moonlit Market")
      assert has_element?(view, "#scene-settings-link")
    end

    test "refuses a name already used by a chat room",
         %{conn: conn, user: user, scenario: scenario} do
      name = unique_room()
      message_fixture(user_scope_fixture(user), name)
      {:ok, view, _html} = live(conn, ~p"/roleplay/new")

      html =
        view
        |> form("#room-form", room: %{name: name, scenario_id: scenario.id})
        |> render_submit()

      assert html =~ "is already taken"
    end

    test "requires an account", %{} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} =
               live(build_conn_with_unique_ip(), ~p"/roleplay/new")
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
