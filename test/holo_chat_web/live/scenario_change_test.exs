defmodule HoloChatWeb.ScenarioChangeTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.Scenarios

  @intro "#messages [data-role='scenario-intro']"

  setup %{conn: conn} do
    gm_user = user_fixture()
    gm = user_scope_fixture(gm_user)

    hogwarts = scenario_fixture(gm, %{"title" => "Hogwarts", "topic" => "Term begins."})
    harry = character_fixture(gm, %{"name" => "Harry"})
    {:ok, _} = Scenarios.cast_character(gm, hogwarts, harry.id)

    risa =
      scenario_fixture(gm, %{
        "title" => "Risa",
        "topic" => "Sun and surf.",
        "description" => "A *pleasure* planet."
      })

    {:ok, risa} = Scenarios.update_scenario_image(gm, risa, :card, gif_binary())
    neelix = character_fixture(gm, %{"name" => "Neelix"})
    {:ok, _} = Scenarios.cast_character(gm, risa, neelix.id)

    %{
      conn: log_in_user(conn, gm_user),
      gm: gm,
      hogwarts: hogwarts,
      risa: risa,
      harry: harry,
      neelix: neelix
    }
  end

  defp start_room(conn, scenario) do
    name = unique_room()
    {:ok, view, _html} = live(conn, ~p"/roleplay/new?scenario=#{scenario.id}")

    {:ok, view, _html} =
      view
      |> form("#room-form", room: %{name: name, scenario_id: scenario.id})
      |> render_submit()
      |> follow_redirect(conn, ~p"/rooms/#{name}")

    {name, view}
  end

  test "a new room plays the chosen scenario with its suggested cast",
       %{conn: conn, hogwarts: hogwarts, harry: harry} do
    {_name, view} = start_room(conn, hogwarts)

    assert has_element?(view, "#scene-title", "Hogwarts")
    assert has_element?(view, "#scene-topic", "Term begins.")
    assert has_element?(view, "#scene-settings-link")
    assert has_element?(view, "#scene-cast [data-character-id='#{harry.id}']")
    assert has_element?(view, "#{@intro}[data-scenario-id='#{hogwarts.id}']", "Hogwarts")
  end

  test "the scenario picker is preselected from the library", %{conn: conn, risa: risa} do
    {:ok, view, _html} = live(conn, ~p"/roleplay/new?scenario=#{risa.id}")

    assert has_element?(view, "#room-form option[value='#{risa.id}'][selected]")
  end

  test "game masters change the scenario and everyone sees the intro",
       %{conn: conn, hogwarts: hogwarts, risa: risa, harry: harry, neelix: neelix} do
    {name, _view} = start_room(conn, hogwarts)
    {:ok, watcher, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{name}")
    {:ok, settings, _html} = live(conn, ~p"/rooms/#{name}/settings")

    assert has_element?(settings, "#current-scenario", "Hogwarts")

    settings
    |> form("#switch-scenario-form", room: %{scenario_id: risa.id})
    |> render_submit()

    intro = "#{@intro}[data-scenario-id='#{risa.id}']"
    assert has_element?(watcher, intro, "This channel changes the scenario to")
    assert has_element?(watcher, intro, "Risa")
    assert has_element?(watcher, "#{intro} em", "pleasure")
    assert has_element?(watcher, "#{intro} img[src='/avatars/#{risa.card_image_id}']")

    assert has_element?(watcher, "#scene-title", "Risa")
    assert has_element?(watcher, "#scene-cast [data-character-id='#{neelix.id}']")
    refute has_element?(watcher, "#scene-cast [data-character-id='#{harry.id}']")
  end

  test "edits of the scenario show up in rooms playing it",
       %{conn: conn, gm: gm, hogwarts: hogwarts} do
    {_name, view} = start_room(conn, hogwarts)

    {:ok, _} = Scenarios.update_scenario(gm, hogwarts, %{"topic" => "The doors are sealed."})

    assert has_element?(view, "#scene-topic", "The doors are sealed.")
  end
end
