defmodule HoloChatWeb.AdminLive.UsersTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.Accounts

  describe "access" do
    test "guests are sent to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/users")
    end

    test "non-admins are sent home", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/users")
    end
  end

  describe "as an admin" do
    setup %{conn: conn} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      %{conn: log_in_user(conn, admin), admin: admin, user: user_fixture()}
    end

    defp open(conn, user) do
      {:ok, view, _html} = live(conn, ~p"/admin/users")
      view |> form("#user-search-form", search: %{query: user.username}) |> render_change()
      view
    end

    defp as(user), do: build_conn_with_unique_ip() |> log_in_user(user)

    test "is linked from the assistant settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant")
      assert has_element?(view, "#admin-users-link[href='/admin/users']")
    end

    test "finds users by name", %{conn: conn, user: user} do
      other = user_fixture()
      view = open(conn, user)

      assert has_element?(view, "#user-#{user.id}", user.username)
      refute has_element?(view, "#user-#{other.id}")
    end

    test "makes a user moderator, who then manages any room", %{conn: conn, user: user} do
      room = roleplay_room_fixture(user_scope_fixture())
      view = open(conn, user)

      view |> element("#role-#{user.id}-moderator") |> render_click()

      assert has_element?(view, "#role-#{user.id}-moderator[data-granted='true']")
      assert {:ok, _settings, _html} = live(as(user), ~p"/rooms/#{room.name}/settings")

      view |> element("#role-#{user.id}-moderator") |> render_click()

      assert has_element?(view, "#role-#{user.id}-moderator[data-granted='false']")
      assert {:error, {:redirect, _}} = live(as(user), ~p"/rooms/#{room.name}/settings")
    end

    test "makes a user library editor, who then edits any scenario",
         %{conn: conn, user: user} do
      scenario = scenario_fixture(user_scope_fixture())
      view = open(conn, user)

      view |> element("#role-#{user.id}-library_editor") |> render_click()

      assert has_element?(view, "#role-#{user.id}-library_editor[data-granted='true']")
      assert {:ok, _form, _html} = live(as(user), ~p"/scenarios/#{scenario.id}/edit")
    end

    test "makes a user news editor, who then writes news", %{conn: conn, user: user} do
      view = open(conn, user)

      view |> element("#role-#{user.id}-news_editor") |> render_click()

      assert has_element?(view, "#role-#{user.id}-news_editor[data-granted='true']")
      assert {:ok, _form, _html} = live(as(user), ~p"/news/new")
    end

    test "makes a user admin, but keeps the own admin rights", %{
      conn: conn,
      admin: admin,
      user: user
    } do
      view = open(conn, user)
      view |> element("#role-#{user.id}-admin") |> render_click()

      assert has_element?(view, "#role-#{user.id}-admin[data-granted='true']")
      assert {:ok, _view, _html} = live(as(user), ~p"/admin/users")

      view = open(conn, admin)
      assert has_element?(view, "#role-#{admin.id}-admin[disabled]")
    end

    test "appoints a game master of an older chat room, and dismisses them",
         %{conn: conn, user: user} do
      chat_room = unique_room()
      message_fixture(user_scope_fixture(), chat_room)
      view = open(conn, user)

      view
      |> form("#appoint-form-#{user.id}", appoint: %{room: chat_room})
      |> render_submit()

      assert has_element?(view, "#mastered-#{user.id}-#{chat_room}")
      {:ok, room_view, _html} = live(as(user), ~p"/rooms/#{chat_room}")
      assert has_element?(room_view, "#start-scene-link")

      # Even the only game master: the room is left to admins and moderators.
      view |> element("#dismiss-#{user.id}-#{chat_room}") |> render_click()

      refute has_element?(view, "#mastered-#{user.id}-#{chat_room}")
    end

    test "refuses to appoint game masters of rooms nobody has used", %{conn: conn, user: user} do
      view = open(conn, user)

      html =
        view
        |> form("#appoint-form-#{user.id}", appoint: %{room: unique_room()})
        |> render_submit()

      assert html =~ "No room with that name"
    end
  end
end
