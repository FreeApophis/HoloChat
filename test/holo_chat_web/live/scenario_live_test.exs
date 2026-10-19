defmodule HoloChatWeb.ScenarioLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.{Accounts, Scenarios}

  describe "the scenario library" do
    test "shows scenarios as cards", %{conn: conn} do
      owner = user_scope_fixture()
      scenario = scenario_fixture(owner, %{"title" => "Risa", "topic" => "Sun and surf."})
      {:ok, scenario} = Scenarios.update_scenario_image(owner, scenario, :card, gif_binary())

      {:ok, view, _html} = live(conn, ~p"/scenarios")

      assert has_element?(view, "#scenario-#{scenario.id}", "Risa")
      assert has_element?(view, "#scenario-#{scenario.id}", "Sun and surf.")

      assert has_element?(
               view,
               "#scenario-#{scenario.id} img[src='/avatars/#{scenario.card_image_id}']"
             )
    end

    test "is linked from the role-play overview", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/roleplay")
      assert has_element?(view, "#scenarios-link[href='/scenarios']")
    end

    test "offers guests neither creating nor starting", %{conn: conn} do
      scenario = scenario_fixture(user_scope_fixture())
      {:ok, view, _html} = live(conn, ~p"/scenarios")

      refute has_element?(view, "#new-scenario-link")
      refute has_element?(view, "#play-scenario-#{scenario.id}")
    end
  end

  describe "as a user" do
    setup :register_and_log_in_user

    test "creates a scenario and then picks its suggested cast", %{conn: conn, user: user} do
      character = character_fixture(user_scope_fixture(user), %{"name" => "Neelix"})
      {:ok, view, _html} = live(conn, ~p"/scenarios")
      assert has_element?(view, "#new-scenario-link[href='/scenarios/new']")

      {:ok, view, _html} = live(conn, ~p"/scenarios/new")

      {:ok, view, _html} =
        view
        |> form("#scenario-form",
          scenario: %{
            title: "Risa",
            topic: "Sun and surf.",
            description: "A pleasure planet.",
            tag_list: "Star Trek"
          }
        )
        |> render_submit()
        |> follow_redirect(conn)

      [scenario] = Enum.filter(Scenarios.list_scenarios(), &(&1.title == "Risa"))
      assert %{description: "A pleasure planet.", tags: ["star-trek"]} = scenario
      assert scenario.owner_id == user.id

      view |> form("#cast-search-form", search: %{query: "Neelix"}) |> render_change()
      view |> element("#search-result-#{character.id} button") |> render_click()

      assert has_element?(view, "#cast-member-#{character.id}")
      assert [%{id: id}] = Scenarios.list_cast(scenario)
      assert id == character.id
    end

    test "edits their scenario and uploads its images", %{conn: conn, user: user} do
      scenario = scenario_fixture(user_scope_fixture(user))
      {:ok, view, _html} = live(conn, ~p"/scenarios/#{scenario.id}/edit")

      assert view
             |> file_input("#scenario-form", :background_image, [
               %{name: "bg.png", content: image_binary(64, 36, {9, 9, 9}), type: "image/png"}
             ])
             |> render_upload("bg.png")

      view
      |> form("#scenario-form", scenario: %{title: "Renamed"})
      |> render_submit()

      updated = Scenarios.get_scenario(scenario.id)
      assert updated.title == "Renamed"
      assert updated.background_image_id
    end

    test "cannot edit someone else's scenario", %{conn: conn} do
      scenario = scenario_fixture(user_scope_fixture())

      assert {:error, {:redirect, %{to: "/scenarios"}}} =
               live(conn, ~p"/scenarios/#{scenario.id}/edit")
    end

    test "starts a room from a scenario card", %{conn: conn} do
      scenario = scenario_fixture(user_scope_fixture())
      {:ok, view, _html} = live(conn, ~p"/scenarios")

      assert has_element?(
               view,
               "#play-scenario-#{scenario.id}[href='/roleplay/new?scenario=#{scenario.id}']"
             )
    end
  end

  test "admins can edit any scenario", %{conn: conn} do
    scenario = scenario_fixture(user_scope_fixture())
    {:ok, admin} = Accounts.set_admin(user_fixture().username, true)

    assert {:ok, _view, _html} =
             conn |> log_in_user(admin) |> live(~p"/scenarios/#{scenario.id}/edit")
  end
end
