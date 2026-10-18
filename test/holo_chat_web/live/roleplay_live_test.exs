defmodule HoloChatWeb.RoleplayLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures

  alias HoloChat.{Accounts, Rooms}

  describe "the role-play overview" do
    test "shows role-play rooms as cards, but not chat rooms", %{conn: conn} do
      gm = user_scope_fixture()

      room =
        roleplay_room_fixture(gm, %{"title" => "The Sunken Keep", "topic" => "Water rises."})

      chat_room = unique_room()
      message_fixture(gm, chat_room)

      {:ok, view, _html} = live(conn, ~p"/roleplay")

      assert has_element?(view, "#room-card-#{room.name}", "The Sunken Keep")
      assert has_element?(view, "#room-card-#{room.name}", "Water rises.")
      assert has_element?(view, "#room-card-#{room.name} a[href='/rooms/#{room.name}']")
      refute has_element?(view, "#room-card-#{chat_room}")
    end

    test "shows the card image", %{conn: conn} do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)
      {:ok, room} = Rooms.update_room_image(gm, room, :card, image_binary(32, 18, {1, 2, 3}))

      {:ok, view, _html} = live(conn, ~p"/roleplay")

      assert has_element?(
               view,
               "#room-card-#{room.name} img[src='/avatars/#{room.card_image_id}']"
             )
    end

    test "offers guests no way to create a room", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/roleplay")
      refute has_element?(view, "#new-room-link")
    end
  end

  describe "creating a role-play room" do
    setup :register_and_log_in_user

    test "makes the creator its game master", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/roleplay")
      assert has_element?(view, "#new-room-link[href='/roleplay/new']")
      {:ok, view, _html} = live(conn, ~p"/roleplay/new")
      name = unique_room()

      {:ok, view, _html} =
        view
        |> form("#room-form", room: %{name: name, title: "Moonlit Market", topic: "Bargains."})
        |> render_submit()
        |> follow_redirect(conn, ~p"/rooms/#{name}")

      assert has_element?(view, "#scene-title", "Moonlit Market")
      assert has_element?(view, "#scene-topic", "Bargains.")
      assert has_element?(view, "#scene-settings-link")
    end

    test "refuses a name already used by a chat room", %{conn: conn, user: user} do
      name = unique_room()
      message_fixture(user_scope_fixture(user), name)
      {:ok, view, _html} = live(conn, ~p"/roleplay/new")

      html =
        view
        |> form("#room-form", room: %{name: name, title: "Taken"})
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
      %{gm: gm, room: roleplay_room_fixture(gm, %{"scenario" => "A storm traps everyone."})}
    end

    test "shows its scene to everyone", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")

      assert has_element?(view, "#scene-title", room.title)
      refute has_element?(view, "#scene-settings-link")

      view |> element("#show-scenario") |> render_click()
      assert has_element?(view, "#scenario", "A storm traps everyone.")
    end

    test "shows its background image", %{conn: conn, gm: gm, room: room} do
      {:ok, room} =
        Rooms.update_room_image(gm, room, :background, image_binary(32, 18, {4, 5, 6}))

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")

      assert has_element?(
               view,
               "#scene-background[style*='/avatars/#{room.background_image_id}']"
             )
    end

    test "updates the scene live when a game master changes it",
         %{conn: conn, gm: gm, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")

      {:ok, _room} = Rooms.update_room(gm, room, %{"topic" => "The doors are sealed."})

      assert has_element?(view, "#scene-topic", "The doors are sealed.")
    end

    test "marks role-play rooms in the room list", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")
      assert has_element?(view, "#room-link-#{room.name}[data-kind='roleplay']")
    end
  end

  describe "scene settings" do
    setup %{conn: conn} do
      gm_user = user_fixture()
      gm = user_scope_fixture(gm_user)
      room = roleplay_room_fixture(gm)
      %{conn: log_in_user(conn, gm_user), gm: gm, room: room}
    end

    test "let a game master edit the scene and upload images", %{conn: conn, room: room} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

      assert view
             |> file_input("#scene-form", :card_image, [
               %{name: "card.png", content: image_binary(64, 36, {9, 9, 9}), type: "image/png"}
             ])
             |> render_upload("card.png")

      {:ok, view, _html} =
        view
        |> form("#scene-form",
          room: %{title: "New Title", topic: "New topic", scenario: "New scenario"}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/rooms/#{room.name}")

      assert has_element?(view, "#scene-title", "New Title")
      updated = Rooms.get_room(room.name)
      assert updated.scenario == "New scenario"
      assert updated.card_image_id
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
