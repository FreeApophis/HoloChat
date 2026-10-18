defmodule HoloChatWeb.UserLive.ProfileTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AvatarFixtures

  alias HoloChat.Accounts

  test "guests are sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/users/profile")
  end

  describe "as a user" do
    setup :register_and_log_in_user

    test "the username in the header links to the profile", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#current-username[href='/users/profile']")
    end

    test "saves the description", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/profile")

      html =
        view
        |> form("#profile-form", user: %{description: "Collects vintage keyboards."})
        |> render_submit()

      assert html =~ "Profile saved"
      assert Accounts.get_user!(user.id).description == "Collects vintage keyboards."
    end

    test "uploads an avatar and shows it", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/profile")
      refute has_element?(view, "#current-avatar")

      avatar =
        file_input(view, "#profile-form", :avatar, [
          %{name: "me.png", content: image_binary(64, 64, {200, 50, 50}), type: "image/png"}
        ])

      assert render_upload(avatar, "me.png") =~ "me.png"

      view |> form("#profile-form", user: %{description: ""}) |> render_submit()

      avatar_id = Accounts.get_user!(user.id).avatar_id
      assert avatar_id
      assert has_element?(view, "#current-avatar[src='/avatars/#{avatar_id}']")
    end

    test "rejects files that aren't images", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/users/profile")

      avatar =
        file_input(view, "#profile-form", :avatar, [
          %{name: "fake.png", content: "not really a png", type: "image/png"}
        ])

      render_upload(avatar, "fake.png")
      html = view |> form("#profile-form", user: %{description: ""}) |> render_submit()

      assert html =~ "could not be read as an image"
      assert Accounts.get_user!(user.id).avatar_id == nil
    end
  end
end
