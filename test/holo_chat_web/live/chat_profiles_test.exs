defmodule HoloChatWeb.ChatProfilesTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.ChatFixtures
  import HoloChatWeb.PresenceHelpers

  alias HoloChat.{Accounts, Assistant, Chat}
  alias HoloChatWeb.Presence

  setup do
    {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
    %{admin: user_scope_fixture(admin), room: unique_room()}
  end

  describe "avatars in messages" do
    test "show the author's uploaded avatar", %{conn: conn, room: room} do
      {:ok, ada} = Accounts.update_user_avatar(user_fixture(), image_binary(8, 8, {9, 9, 9}))
      message = message_fixture(user_scope_fixture(ada), room)

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      assert has_element?(view, "#messages-#{message.id} img[src='/avatars/#{ada.avatar_id}']")
    end

    test "fall back to the initial without an avatar", %{conn: conn, room: room} do
      message = message_fixture(user_scope_fixture(), room)

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      refute has_element?(view, "#messages-#{message.id} img")
    end

    test "show the persona's avatar on its replies", %{conn: conn, room: room, admin: admin} do
      {:ok, sage} = Assistant.create_persona(admin, %{"name" => "Sage"})
      {:ok, sage} = Assistant.update_persona_avatar(admin, sage, image_binary(8, 8, {7, 7, 7}))
      {:ok, reply} = Chat.create_assistant_message(room, "Sage", "Hi", persona_id: sage.id)

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      assert has_element?(view, "#messages-#{reply.id} img[src='/avatars/#{sage.avatar_id}']")
    end
  end

  describe "profile cards" do
    test "show a person's avatar, name and description", %{conn: conn, room: room} do
      {:ok, ada} = Accounts.update_user_profile(user_fixture(), %{"description" => "Stargazer."})
      message = message_fixture(user_scope_fixture(ada), room)
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      refute has_element?(view, "#profile-card")
      view |> element("#messages-#{message.id} [data-role='author']") |> render_click()

      assert has_element?(view, "#profile-card", ada.username)
      assert has_element?(view, "#profile-card", "Stargazer.")
      refute has_element?(view, "#profile-card [data-role='assistant-badge']")

      assert has_element?(view, "#profile-card a#profile-page-link[href='/u/#{ada.username}']")

      view |> element("#close-profile") |> render_click()
      refute has_element?(view, "#profile-card")
    end

    test "show a persona's public description but never its prompt",
         %{conn: conn, room: room, admin: admin} do
      {:ok, sage} =
        Assistant.create_persona(admin, %{
          "name" => "Sage",
          "description" => "Reviews your code.",
          "system_prompt" => "SECRET INSTRUCTIONS"
        })

      {:ok, reply} = Chat.create_assistant_message(room, "Sage", "Hi", persona_id: sage.id)
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      view |> element("#messages-#{reply.id} [data-role='author']") |> render_click()

      assert has_element?(view, "#profile-card", "Reviews your code.")
      assert has_element?(view, "#profile-card [data-role='assistant-badge']")
      refute render(view) =~ "SECRET INSTRUCTIONS"
    end

    test "show the current profile after a rename", %{conn: conn, room: room, admin: admin} do
      {:ok, sage} = Assistant.create_persona(admin, %{"name" => "Sage"})
      {:ok, reply} = Chat.create_assistant_message(room, "Sage", "Hi", persona_id: sage.id)
      {:ok, _} = Assistant.update_persona(admin, sage, %{"name" => "Oracle"})

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")
      view |> element("#messages-#{reply.id} [data-role='author']") |> render_click()

      assert has_element?(view, "#profile-card", "Oracle")
    end
  end

  describe "the online list" do
    setup %{room: room} do
      Presence.subscribe(room)
      on_exit(&await_presence_fetchers/0)
      :ok
    end

    test "shows avatars and opens profile cards", %{room: room} do
      {:ok, ada} = Accounts.update_user_avatar(user_fixture(), image_binary(8, 8, {3, 3, 3}))
      {:ok, ada} = Accounts.update_user_profile(ada, %{"description" => "Online now."})

      {:ok, _ada_view, _html} =
        build_conn_with_unique_ip() |> log_in_user(ada) |> live(~p"/rooms/#{room}")

      {:ok, view, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{room}")

      assert has_element?(view, "#online-users img[src='/avatars/#{ada.avatar_id}']")

      view |> element("#online-users [data-user-id='#{ada.id}']") |> render_click()
      assert has_element?(view, "#profile-card", "Online now.")
    end
  end
end
