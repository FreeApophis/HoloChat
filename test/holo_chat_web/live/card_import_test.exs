defmodule HoloChatWeb.CardImportTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AvatarFixtures
  import HoloChat.CardsFixtures
  import HoloChat.CharactersFixtures

  alias HoloChat.{Characters, Scenarios}

  defp upload_card(view, name, content, type \\ "image/png") do
    view
    |> file_input("#card-upload-form", :card, [%{name: name, content: content, type: type}])
    |> render_upload(name)

    view |> form("#card-upload-form") |> render_submit()
  end

  defp hermione_card(tag) do
    card_png([
      {"chara",
       card_v2(%{
         "name" => "Hermione",
         "description" => "{{char}} is a bright Gryffindor witch.",
         "personality" => "Clever, bossy, loyal.",
         "scenario" => "{{char}} studies in the library at midnight.",
         "first_mes" => "*{{char}} looks up from her book.* Oh, it's you, {{user}}.",
         "mes_example" => "<START>\n{{user}}: Hi\n{{char}}: Shh, this is a library.",
         "tags" => [tag]
       })}
    ])
  end

  describe "importing a card" do
    setup :register_and_log_in_user

    test "splits a card into a character and a scenario with that cast", %{
      conn: conn,
      user: user
    } do
      tag = unique_tag()
      {:ok, view, _html} = live(conn, ~p"/characters")
      assert has_element?(view, "#import-card-link[href='/characters/import']")

      {:ok, view, _html} = live(conn, ~p"/characters/import")
      upload_card(view, "hermione.png", hermione_card(tag))

      assert has_element?(view, "#card-avatar-preview")
      assert has_element?(view, "#character_name[value='Hermione']")

      assert has_element?(
               view,
               "#character_description",
               "Hermione is a bright Gryffindor witch."
             )

      assert has_element?(view, "#scenario_description", "Hermione studies in the library")
      refute has_element?(view, "#character_example_dialogue")

      {:ok, view, _html} =
        view
        |> form("#card-import-form",
          character: %{personality: "Clever and loyal."},
          scenario: %{title: "Midnight library"}
        )
        |> render_submit()
        |> follow_redirect(conn)

      assert has_element?(view, "#character-name", "Hermione")
      assert has_element?(view, "#character-personality", "Clever and loyal.")
      assert has_element?(view, "#character-avatar img")
      assert has_element?(view, "[data-tag='#{tag}']")

      [scenario] = Scenarios.list_scenarios_by_owner(user.id)
      assert scenario.title == "Midnight library"
      assert scenario.tags == [tag]
      assert [%{name: "Hermione"}] = Scenarios.list_cast(scenario)
    end

    test "imports only the character when the scenario is left out", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/characters/import")
      upload_card(view, "hermione.png", hermione_card(unique_tag()))

      {:ok, _view, _html} =
        view
        |> form("#card-import-form", import: %{with_scenario: "false"})
        |> render_submit()
        |> follow_redirect(conn)

      assert [%{name: "Hermione"}] = Characters.list_characters_by_owner(user.id)
      assert Scenarios.list_scenarios_by_owner(user.id) == []
    end

    test "shows validation errors and imports nothing", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/characters/import")
      upload_card(view, "hermione.png", hermione_card(unique_tag()))

      view
      |> form("#card-import-form", scenario: %{title: ""})
      |> render_submit()

      assert has_element?(view, "#card-import-form", "can't be blank")
      assert Characters.list_characters_by_owner(user.id) == []
    end

    test "shows right away which fields are too long, and by how much", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/characters/import")
      card = card_v2(%{"name" => "Verbose", "description" => String.duplicate("a", 4100)})
      upload_card(view, "verbose.png", card_png([{"chara", card}]))

      assert has_element?(view, "#character_description-counter[data-over]", "4100 / 4000")
      assert has_element?(view, "#card-character", "should be at most 4000 character(s)")
      refute has_element?(view, "#character_personality-counter[data-over]")
    end

    test "reads cards saved as JSON", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/characters/import")
      json = Jason.encode!(card_v2(%{"name" => "Luna"}))
      upload_card(view, "luna.json", json, "application/json")

      assert has_element?(view, "#character_name[value='Luna']")
      refute has_element?(view, "#card-avatar-preview")
    end

    test "rejects files that are no card", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/characters/import")
      upload_card(view, "photo.png", image_binary(4, 4, {0, 0, 0}))

      assert has_element?(view, "#card-error")
      refute has_element?(view, "#card-import-form")
    end
  end

  test "guests are sent to log in", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/characters/import")
  end
end
