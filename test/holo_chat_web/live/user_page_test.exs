defmodule HoloChatWeb.UserPageTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.RoomsFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.Accounts

  setup do
    user = user_fixture()
    {:ok, user} = Accounts.update_user_profile(user, %{"description" => "Likes **jazz**."})
    {:ok, user} = Accounts.update_user_avatar(user, gif_binary())
    %{user: user, scope: user_scope_fixture(user)}
  end

  test "shows a user's profile, roles and what they made", %{conn: conn, user: user, scope: scope} do
    room = roleplay_room_fixture(scope)
    _scenario = scenario_fixture(scope, %{"title" => "Sunset Beach"})
    character = character_fixture(scope, %{"name" => "Neelix #{unique_tag()}"})
    {:ok, _} = Accounts.set_role(role_scope_fixture(:admin), user.id, :news_editor, true)

    {:ok, view, _html} = live(conn, ~p"/u/#{user.username}")

    assert has_element?(view, "#user-name", user.username)
    assert has_element?(view, "#user-avatar img[src='/avatars/#{user.avatar_id}']")
    assert has_element?(view, "#user-description strong", "jazz")
    assert has_element?(view, "#user-roles", "News editor")
    assert has_element?(view, "#user-joined")
    assert has_element?(view, "#user-rooms a[href='/rooms/#{room.name}']")
    assert has_element?(view, "#user-scenarios a", "Sunset Beach")
    assert has_element?(view, "#user-characters a[href='/characters/#{character.id}']")
  end

  test "finds users regardless of case", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, ~p"/u/#{String.upcase(user.username)}")

    assert has_element?(view, "#user-name", user.username)
  end

  test "sends visitors of unknown users home", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/", flash: %{"error" => _}}}} =
             live(conn, ~p"/u/nobody_here")
  end
end
