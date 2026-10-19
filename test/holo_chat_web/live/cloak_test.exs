defmodule HoloChatWeb.CloakTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures
  import HoloChatWeb.PresenceHelpers

  alias HoloChat.{Accounts, Rooms}
  alias HoloChatWeb.Presence

  setup %{conn: conn} do
    user = user_fixture()
    {:ok, user} = Accounts.update_user_profile(user, %{"description" => "Likes jazz."})

    riker =
      character_fixture(user_scope_fixture(), %{
        "name" => "Will Riker #{unique_tag()}",
        "description" => "First officer."
      })

    on_exit(&await_presence_fetchers/0)
    %{conn: log_in_user(conn, user), user: user, riker: riker}
  end

  defp wear(view, character) do
    view |> form("#wardrobe-search", wardrobe: %{query: character.name}) |> render_change()
    view |> element("#wardrobe-option-#{character.id}") |> render_click()
  end

  defp say(view, body) do
    view |> form("#message-form", message: %{body: body}) |> render_submit()
  end

  defp message_id(view, body) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#messages > div:has([data-role='message-body'])")
    |> Enum.find(&(LazyHTML.text(&1) =~ body))
    |> LazyHTML.attribute("id")
    |> hd()
  end

  test "a player wears a character from the wardrobe and speaks as them",
       %{conn: conn, user: user, riker: riker} do
    {:ok, view, _html} = live(conn, ~p"/rooms/#{unique_room()}")

    wear(view, riker)
    assert has_element?(view, "#current-cloak", riker.name)

    say(view, "Number one reporting.")
    id = message_id(view, "Number one reporting.")

    assert has_element?(view, "##{id} [data-role='author']", riker.name)
    assert has_element?(view, "##{id} [data-role='actor-badge']", user.username)
    assert has_element?(view, "##{id} [data-role='cloak-avatar']")
    assert has_element?(view, "##{id} [data-role='actor-avatar']")
    refute has_element?(view, "##{id} [data-role='assistant-badge']")
  end

  test "the profile card shows the actor and the role", %{conn: conn, user: user, riker: riker} do
    {:ok, view, _html} = live(conn, ~p"/rooms/#{unique_room()}")
    wear(view, riker)
    say(view, "Make it so.")

    view
    |> element("##{message_id(view, "Make it so.")} [data-role='author']")
    |> render_click()

    assert has_element?(view, "#profile-actor", user.username)
    assert has_element?(view, "#profile-actor", "Likes jazz.")
    assert has_element?(view, "#profile-role", riker.name)
    assert has_element?(view, "#profile-role", "First officer.")
  end

  test "cloaks are per room, and taking one off keeps earlier messages",
       %{conn: conn, user: user, riker: riker} do
    room = unique_room()
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")
    wear(view, riker)
    say(view, "In costume.")

    {:ok, elsewhere, _html} = live(conn, ~p"/rooms/#{unique_room()}")
    refute has_element?(elsewhere, "#current-cloak")

    view |> element("#take-off-cloak") |> render_click()
    refute has_element?(view, "#current-cloak")
    say(view, "Out of costume.")

    assert has_element?(
             view,
             "##{message_id(view, "In costume.")} [data-role='author']",
             riker.name
           )

    assert has_element?(
             view,
             "##{message_id(view, "Out of costume.")} [data-role='author']",
             user.username
           )
  end

  test "others see the cloak in front of the player in the online list",
       %{conn: conn, user: user, riker: riker} do
    room = unique_room()
    Presence.subscribe(room)
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")
    {:ok, watcher, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{room}")

    wear(view, riker)
    await_presence(%{cloak_id: riker.id})

    person = "#online-users [data-user-id='#{user.id}'][data-cloak-id='#{riker.id}']"
    assert has_element?(watcher, "#{person} [data-role='cloak-avatar']")
    assert has_element?(watcher, "#{person} [data-role='actor-avatar']")
  end

  test "a character is worn by one player per room", %{riker: riker} do
    room = unique_room()
    first = build_conn_with_unique_ip() |> log_in_user(user_fixture())
    second = build_conn_with_unique_ip() |> log_in_user(user_fixture())
    {:ok, first_view, _html} = live(first, ~p"/rooms/#{room}")
    {:ok, second_view, _html} = live(second, ~p"/rooms/#{room}")

    wear(first_view, riker)
    html = wear(second_view, riker)

    assert html =~ "already wearing"
    refute has_element?(second_view, "#current-cloak")
  end

  test "guests have no wardrobe", %{} do
    {:ok, view, _html} = live(build_conn_with_unique_ip(), ~p"/rooms/#{unique_room()}")
    refute has_element?(view, "#wardrobe-toggle")
  end

  describe "characters the AI plays in the room" do
    setup %{riker: riker} do
      gm_user = user_fixture()
      gm = user_scope_fixture(gm_user)
      room = roleplay_room_fixture(gm)
      {:ok, _} = Rooms.cast_character(gm, room, riker.id)
      %{gm: gm, gm_user: gm_user, room: room}
    end

    test "can be taken over by default", %{conn: conn, room: room, riker: riker} do
      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")
      wear(view, riker)

      assert has_element?(view, "#current-cloak", riker.name)
    end

    test "can't be worn when the game master forbids it",
         %{conn: conn, gm_user: gm_user, room: room, riker: riker} do
      gm_conn = build_conn_with_unique_ip() |> log_in_user(gm_user)
      {:ok, settings, _html} = live(gm_conn, ~p"/rooms/#{room.name}/settings")

      settings
      |> form("#scene-form", room: %{cloak_policy: "forbid"})
      |> render_submit()

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")
      html = wear(view, riker)

      assert html =~ "plays this character"
      refute has_element?(view, "#current-cloak")
    end
  end
end
