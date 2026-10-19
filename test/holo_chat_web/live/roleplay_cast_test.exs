defmodule HoloChatWeb.RoleplayCastTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.RoomsFixtures

  alias HoloChat.Rooms

  setup %{conn: conn} do
    gm_user = user_fixture()
    gm = user_scope_fixture(gm_user)
    tag = unique_tag()
    room = roleplay_room_fixture(gm, %{"tag_list" => tag})
    %{conn: log_in_user(conn, gm_user), gm: gm, room: room, tag: tag}
  end

  describe "scene settings" do
    test "suggest characters that share the scene's tags and cast them",
         %{conn: conn, gm: gm, room: room, tag: tag} do
      fitting = character_fixture(gm, %{"name" => "Harry", "tag_list" => tag})
      unrelated = character_fixture(gm, %{"name" => "Gandalf"})

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

      assert has_element?(view, "#suggestion-#{fitting.id}", "Harry")
      refute has_element?(view, "#suggestion-#{unrelated.id}")

      view |> element("#cast-#{fitting.id}") |> render_click()

      assert has_element?(view, "#cast-member-#{fitting.id}")
      refute has_element?(view, "#suggestion-#{fitting.id}")
    end

    test "rank suggestions by how many tags they share", %{conn: conn, gm: gm} do
      [a, b] = [unique_tag(), unique_tag()]
      room = roleplay_room_fixture(gm, %{"tag_list" => "#{a}, #{b}"})
      one = character_fixture(gm, %{"tag_list" => a})
      both = character_fixture(gm, %{"tag_list" => "#{a}, #{b}"})

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#suggested-characters [id^='suggestion-']")
        |> LazyHTML.attribute("id")

      assert ids == ["suggestion-#{both.id}", "suggestion-#{one.id}"]
    end

    test "find any character by name", %{conn: conn, gm: gm, room: room} do
      name = "Wanderer #{unique_tag()}"
      character = character_fixture(gm, %{"name" => name})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

      view |> form("#cast-search-form", search: %{query: name}) |> render_change()
      view |> element("#search-result-#{character.id} button") |> render_click()

      assert has_element?(view, "#cast-member-#{character.id}")
    end

    test "remove a character from the cast", %{conn: conn, gm: gm, room: room} do
      character = character_fixture(gm)
      {:ok, _room} = Rooms.cast_character(gm, room, character.id)
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

      view |> element("#uncast-#{character.id}") |> render_click()

      refute has_element?(view, "#cast-member-#{character.id}")
    end
  end

  describe "in the scene" do
    test "the cast is shown and opens profile cards", %{gm: gm, room: room} do
      character = character_fixture(gm, %{"name" => "Hagrid", "description" => "Keeper of keys."})
      {:ok, _room} = Rooms.cast_character(gm, room, character.id)

      {:ok, view, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{room.name}")

      view |> element("#scene-cast [data-character-id='#{character.id}']") |> render_click()
      assert has_element?(view, "#profile-card", "Keeper of keys.")
    end

    test "cast changes show up live", %{gm: gm, room: room} do
      character = character_fixture(gm)
      {:ok, view, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{room.name}")

      {:ok, _room} = Rooms.cast_character(gm, room, character.id)

      assert has_element?(view, "#scene-cast [data-character-id='#{character.id}']")
    end

    test "the overview card shows the scene's tags", %{room: room, tag: tag} do
      {:ok, view, _html} = live(build_conn_with_unique_ip(), ~p"/roleplay")
      assert has_element?(view, "#scenario-card-#{room.scenario_id} [data-tag='#{tag}']")
    end
  end
end
