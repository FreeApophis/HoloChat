defmodule HoloChatWeb.AdminLive.PromptTemplateFormTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures

  alias HoloChat.{Accounts, Assistant}

  test "non-admins can't open the form", %{conn: conn} do
    conn = log_in_user(conn, user_fixture())
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/assistant/templates/new")
  end

  describe "as an admin" do
    setup %{conn: conn} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      %{conn: log_in_user(conn, admin), admin: user_scope_fixture(admin)}
    end

    test "creates a template, starting from the built-in one", %{conn: conn} do
      {:ok, overview, _html} = live(conn, ~p"/admin/assistant")
      assert has_element?(overview, "#prompt-template-standard")

      {:ok, view, _html} =
        overview |> element("#new-prompt-template") |> render_click() |> follow_redirect(conn)

      assert has_element?(view, "#prompt-template-form textarea", "You are playing {{char}}")
      assert has_element?(view, "#placeholder-help", "{{others}}")

      name = "Rhymes #{System.unique_integer([:positive])}"

      {:ok, overview, html} =
        view
        |> form("#prompt-template-form",
          prompt_template: %{name: name, body: "{{char}} speaks in rhyme."}
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/assistant")

      assert html =~ "Template saved"
      template = Enum.find(Assistant.list_prompt_templates(), &(&1.name == name))
      assert template.body == "{{char}} speaks in rhyme."
      assert has_element?(overview, "#prompt-template-#{template.id}", name)
    end

    test "shows the built-in template read-only", %{conn: conn} do
      {:ok, overview, _html} = live(conn, ~p"/admin/assistant")

      {:ok, view, _html} =
        overview
        |> element("#view-prompt-template-standard")
        |> render_click()
        |> follow_redirect(conn)

      assert has_element?(view, "#standard-template-body", "You are playing {{char}}")
      assert has_element?(view, "#placeholder-help", "{{others}}")
      refute has_element?(view, "#prompt-template-form")

      {:ok, new_view, _html} =
        view |> element("#copy-standard-template") |> render_click() |> follow_redirect(conn)

      assert has_element?(new_view, "#prompt-template-form textarea", "You are playing {{char}}")
    end

    test "writes templates in another language, starting from its Standard",
         %{conn: conn} do
      {:ok, overview, _html} = live(conn, ~p"/admin/assistant")
      assert has_element?(overview, "#prompt-template-standard [data-role='language']", "EN")
      assert has_element?(overview, "#prompt-template-standard-de [data-role='language']", "DE")

      {:ok, standard, _html} =
        overview
        |> element("#view-prompt-template-standard-de")
        |> render_click()
        |> follow_redirect(conn)

      assert has_element?(standard, "#standard-template-body", "Du spielst {{char}}")

      {:ok, view, _html} =
        standard |> element("#copy-standard-template") |> render_click() |> follow_redirect(conn)

      assert has_element?(view, "#prompt-template-form textarea", "Du spielst {{char}}")
      assert has_element?(view, "#prompt-template-form select option[value='de'][selected]")

      name = "Reime #{System.unique_integer([:positive])}"

      {:ok, overview, _html} =
        view
        |> form("#prompt-template-form", prompt_template: %{name: name, body: "Reime, {{char}}."})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/assistant")

      template = Enum.find(Assistant.list_prompt_templates(), &(&1.name == name))
      assert template.language == "de"

      assert has_element?(
               overview,
               "#prompt-template-#{template.id} [data-role='language']",
               "DE"
             )
    end

    test "edits and deletes a template", %{conn: conn, admin: admin} do
      {:ok, template} =
        Assistant.create_prompt_template(admin, %{
          "name" => "Terse #{System.unique_integer([:positive])}",
          "body" => "Be brief, {{char}}."
        })

      {:ok, view, _html} = live(conn, ~p"/admin/assistant/templates/#{template.id}/edit")

      {:ok, overview, _html} =
        view
        |> form("#prompt-template-form", prompt_template: %{body: "Be very brief, {{char}}."})
        |> render_submit()
        |> follow_redirect(conn, ~p"/admin/assistant")

      assert Assistant.get_prompt_template(template.id).body == "Be very brief, {{char}}."

      overview |> element("#delete-prompt-template-#{template.id}") |> render_click()

      refute has_element?(overview, "#prompt-template-#{template.id}")
      assert Assistant.get_prompt_template(template.id) == nil
    end

    test "requires a name and a body", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant/templates/new")

      view
      |> form("#prompt-template-form", prompt_template: %{name: "", body: ""})
      |> render_submit()

      assert has_element?(view, "#prompt-template-form", "can't be blank")
    end
  end
end
