defmodule HoloChatWeb.AdminLive.PersonaFormTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures

  alias HoloChat.{Accounts, Assistant}

  test "non-admins can't open the form", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/assistant/personas/new")
  end

  describe "as an admin" do
    setup %{conn: conn} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      %{conn: log_in_user(conn, admin), admin: user_scope_fixture(admin)}
    end

    test "creates a persona and returns to the overview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant/personas/new")

      assert has_element?(view, "#persona-form textarea[name='persona[system_prompt]']")

      {:ok, overview, html} =
        view
        |> form("#persona-form",
          persona: %{name: "Sage", rooms: "help, #Lobby", system_prompt: "You are {name}."}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/assistant")

      assert html =~ "Persona saved"

      assert [%{name: "Sage", rooms: ["help", "lobby"], system_prompt: "You are {name}."} = sage] =
               Assistant.list_personas()

      assert has_element?(overview, "#persona-#{sage.id}", "@Sage")
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant/personas/new")

      html =
        view
        |> form("#persona-form", persona: %{name: "Sage", rooms: "help, not valid"})
        |> render_submit()

      assert html =~ "contains an invalid room name: not valid"
      assert Assistant.list_personas() == []
    end

    test "edits a persona", %{conn: conn, admin: admin} do
      {:ok, persona} = Assistant.create_persona(admin, %{"name" => "Sage", "rooms" => ["help"]})
      {:ok, view, _html} = live(conn, ~p"/admin/assistant/personas/#{persona.id}/edit")

      assert has_element?(view, "#persona-form input[name='persona[name]'][value='Sage']")
      assert has_element?(view, "#persona-form input[name='persona[rooms]'][value='help']")

      view
      |> form("#persona-form", persona: %{rooms: "help, lobby", temperature: "0.2"})
      |> render_submit()

      assert %{rooms: ["help", "lobby"], temperature: 0.2} = Assistant.get_persona!(persona.id)
    end
  end

  describe "persona profile" do
    import HoloChat.AvatarFixtures

    setup %{conn: conn} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      {:ok, persona} = Assistant.create_persona(user_scope_fixture(admin), %{"name" => "Sage"})
      %{conn: log_in_user(conn, admin), persona: persona}
    end

    test "saves the public description", %{conn: conn, persona: persona} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant/personas/#{persona.id}/edit")

      view
      |> form("#persona-form", persona: %{description: "Your friendly code reviewer."})
      |> render_submit()

      assert Assistant.get_persona!(persona.id).description == "Your friendly code reviewer."
    end

    test "uploads an avatar", %{conn: conn, persona: persona} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant/personas/#{persona.id}/edit")

      avatar =
        file_input(view, "#persona-form", :avatar, [
          %{
            name: "sage.jpg",
            content: image_binary(48, 48, {20, 120, 60}, :jpg),
            type: "image/jpeg"
          }
        ])

      render_upload(avatar, "sage.jpg")
      view |> form("#persona-form") |> render_submit()

      assert Assistant.get_persona!(persona.id).avatar_id
    end

    test "shows avatars in the overview", %{conn: conn, persona: persona} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant/personas/#{persona.id}/edit")

      avatar =
        file_input(view, "#persona-form", :avatar, [
          %{name: "sage.png", content: image_binary(8, 8, {1, 1, 1}), type: "image/png"}
        ])

      render_upload(avatar, "sage.png")
      view |> form("#persona-form") |> render_submit()
      avatar_id = Assistant.get_persona!(persona.id).avatar_id

      {:ok, overview, _html} = live(conn, ~p"/admin/assistant")
      assert has_element?(overview, "#persona-#{persona.id} img[src='/avatars/#{avatar_id}']")
    end
  end

  describe "overview actions" do
    setup %{conn: conn} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      {:ok, persona} = Assistant.create_persona(user_scope_fixture(admin), %{"name" => "Sage"})
      %{conn: log_in_user(conn, admin), persona: persona}
    end

    test "link to creating and editing personas", %{conn: conn, persona: persona} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant")

      assert has_element?(view, "#new-persona[href='/admin/assistant/personas/new']")

      assert has_element?(
               view,
               "#edit-persona-#{persona.id}[href='/admin/assistant/personas/#{persona.id}/edit']"
             )
    end

    test "delete a persona", %{conn: conn, persona: persona} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant")

      view |> element("#delete-persona-#{persona.id}") |> render_click()

      refute has_element?(view, "#persona-#{persona.id}")
      assert Assistant.list_personas() == []
    end
  end
end
