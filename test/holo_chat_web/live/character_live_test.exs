defmodule HoloChatWeb.CharacterLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.CharactersFixtures

  alias HoloChat.{Accounts, Characters}

  describe "the character library" do
    test "shows characters as cards with their tags", %{conn: conn} do
      tag = unique_tag()

      hermione =
        character_fixture(user_scope_fixture(), %{"name" => "Hermione", "tag_list" => tag})

      {:ok, view, _html} = live(conn, ~p"/characters")

      assert has_element?(view, "#character-#{hermione.id}", "Hermione")
      assert has_element?(view, "#character-#{hermione.id} [data-tag='#{tag}']")
      refute has_element?(view, "#new-character-link")
    end

    test "filters by tag", %{conn: conn} do
      tag = unique_tag()
      tagged = character_fixture(user_scope_fixture(), %{"tag_list" => tag})
      other = character_fixture(user_scope_fixture())

      {:ok, view, _html} = live(conn, ~p"/characters?tag=#{tag}")

      assert has_element?(view, "#character-#{tagged.id}")
      refute has_element?(view, "#character-#{other.id}")
      assert has_element?(view, "#tag-filter", tag)
    end

    test "shows a character's sheet", %{conn: conn} do
      character =
        character_fixture(user_scope_fixture(), %{
          "name" => "Luna",
          "description" => "Dreamy Ravenclaw.",
          "personality" => "Calm, odd, kind."
        })

      {:ok, view, _html} = live(conn, ~p"/characters/#{character.id}")

      assert has_element?(view, "#character-name", "Luna")
      assert has_element?(view, "#character-description", "Dreamy Ravenclaw.")
      assert has_element?(view, "#character-personality", "Calm, odd, kind.")
      refute has_element?(view, "#edit-character-link")
    end
  end

  describe "creating and editing characters" do
    setup :register_and_log_in_user

    test "creates a character with an avatar", %{conn: conn} do
      tag = unique_tag()
      {:ok, view, _html} = live(conn, ~p"/characters")
      assert has_element?(view, "#new-character-link[href='/characters/new']")

      {:ok, view, _html} = live(conn, ~p"/characters/new")

      view
      |> file_input("#character-form", :avatar, [
        %{name: "ron.png", content: image_binary(16, 16, {200, 80, 20}), type: "image/png"}
      ])
      |> render_upload("ron.png")

      {:ok, view, _html} =
        view
        |> form("#character-form",
          character: %{
            name: "Ron",
            tag_list: "#{tag}, Hogwarts",
            description: "Loyal friend."
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(view, "#character-name", "Ron")
      assert has_element?(view, "[data-tag='#{tag}']")
      assert has_element?(view, "[data-tag='hogwarts']")
      assert has_element?(view, "#character-avatar img")
      assert has_element?(view, "#edit-character-link")
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/characters/new")

      html = view |> form("#character-form", character: %{name: ""}) |> render_submit()

      assert html =~ "can&#39;t be blank"
    end

    test "lets the owner edit and delete", %{conn: conn, user: user} do
      character = character_fixture(user_scope_fixture(user), %{"name" => "Neville"})
      {:ok, view, _html} = live(conn, ~p"/characters/#{character.id}/edit")

      {:ok, view, _html} =
        view
        |> form("#character-form", character: %{name: "Neville Longbottom"})
        |> render_submit()
        |> follow_redirect(conn, ~p"/characters/#{character.id}")

      assert has_element?(view, "#character-name", "Neville Longbottom")

      {:ok, _view, _html} =
        view
        |> element("#delete-character")
        |> render_click()
        |> follow_redirect(conn, ~p"/characters")

      assert Characters.get_character(character.id) == nil
    end

    test "keeps others out of the editor", %{conn: conn} do
      character = character_fixture(user_scope_fixture())

      assert {:error, {:redirect, %{to: path}}} =
               live(conn, ~p"/characters/#{character.id}/edit")

      assert path == ~p"/characters/#{character.id}"
    end

    test "lets admins edit any character" do
      character = character_fixture(user_scope_fixture())
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      conn = build_conn_with_unique_ip() |> log_in_user(admin)

      assert {:ok, _view, _html} = live(conn, ~p"/characters/#{character.id}/edit")
    end
  end

  test "creating needs an account" do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} =
             live(build_conn_with_unique_ip(), ~p"/characters/new")
  end
end
