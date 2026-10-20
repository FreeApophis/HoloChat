defmodule HoloChatWeb.ChatMentionsTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures
  import HoloChatWeb.PresenceHelpers

  alias HoloChat.Rooms
  alias HoloChatWeb.Presence

  setup %{conn: conn} do
    me = user_scope_fixture()
    %{conn: log_in_user(conn, me.user), me: me, bob: user_scope_fixture()}
  end

  # Rendering first waits for the view to handle what was broadcast. The
  # layout adds the suffix to the first title only; browsers keep it.
  defp title(view) do
    _ = render(view)
    view |> page_title() |> String.replace_suffix(" · HoloChat", "")
  end

  defp say(scope, room, body) do
    {:ok, message} = Rooms.post_message(scope, room, %{"body" => body})
    message
  end

  test "highlights messages that address you, not others or code", %{conn: conn, me: me, bob: bob} do
    room = unique_room()
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

    to_me = say(bob, room, "@#{String.upcase(me.user.username)}, look!")
    to_others = say(bob, room, "@somebody_else hi")
    in_code = say(bob, room, "`@#{me.user.username}`")
    own = say(me, room, "I am @#{me.user.username}")

    assert has_element?(view, "#messages-#{to_me.id}[data-mentions-me]")
    refute has_element?(view, "#messages-#{to_others.id}[data-mentions-me]")
    refute has_element?(view, "#messages-#{in_code.id}[data-mentions-me]")
    refute has_element?(view, "#messages-#{own.id}[data-mentions-me]")
    assert has_element?(view, "#messages-#{to_me.id} [data-role='message-body'] .mention")
  end

  test "counts the character you wear in a role-play room", %{conn: conn, me: me, bob: bob} do
    gm = user_scope_fixture()
    room = roleplay_room_fixture(gm)
    neelix = character_fixture(gm, %{"name" => "Neelix #{unique_tag()}"})
    {:ok, _} = Rooms.wear_character(me, room.name, neelix.id)

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")
    message = say(bob, room.name, "@#{neelix.name}, more coffee please")

    assert has_element?(view, "#messages-#{message.id}[data-mentions-me]")
  end

  describe "autocomplete" do
    setup do
      on_exit(&await_presence_fetchers/0)
    end

    test "offers the people in the room, by name and character, and rooms",
         %{conn: conn, me: me, bob: bob} do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)
      riker = character_fixture(gm, %{"name" => "Riker #{unique_tag()}"})
      {:ok, _} = Rooms.wear_character(bob, room.name, riker.id)
      other = unique_room()

      Presence.subscribe(room.name)

      {:ok, _bob_view, _html} =
        live(log_in_user(build_conn_with_unique_ip(), bob.user), ~p"/rooms/#{room.name}")

      await_presence(%{name: bob.user.username})
      {:ok, view, _html} = live(conn, ~p"/rooms/#{other}")
      view |> element("#room-tab-lobby a") |> render_click()
      view |> form("#room-form", room: %{name: room.name}) |> render_submit()

      [composer] =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#composer")
        |> Enum.to_list()

      [mentions] = LazyHTML.attribute(composer, "data-mentions")
      [rooms] = LazyHTML.attribute(composer, "data-rooms")

      assert bob.user.username in Jason.decode!(mentions)
      assert riker.name in Jason.decode!(mentions)
      refute me.user.username in Jason.decode!(mentions)
      assert Enum.all?(["lobby", other, room.name], &(&1 in Jason.decode!(rooms)))
      assert has_element?(view, "#composer[phx-hook] #composer-suggestions[phx-update='ignore']")
    end
  end

  test "marks other rooms' tabs and counts mentions in the title until visited",
       %{conn: conn, me: me, bob: bob} do
    [other, current] = [unique_room(), unique_room()]
    {:ok, view, _html} = live(conn, ~p"/rooms/#{other}")
    view |> form("#room-form", room: %{name: current}) |> render_submit()

    say(bob, other, "just chatting")
    refute has_element?(view, "#tab-mention-#{other}")
    assert title(view) == "##{current}"

    say(bob, other, "@#{me.user.username} are you there?")
    say(bob, other, "@#{me.user.username} hello??")

    assert has_element?(view, "#tab-mention-#{other}")
    assert title(view) == "(2) ##{current}"

    view |> element("#room-tab-#{other} a") |> render_click()

    refute has_element?(view, "#tab-mention-#{other}")
    assert title(view) == "##{other}"
  end

  test "counts mentions in the open room while the page is in the background",
       %{conn: conn, me: me, bob: bob} do
    room = unique_room()
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

    say(bob, room, "@#{me.user.username} seen while looking")
    assert title(view) == "##{room}"

    view |> element("#chat") |> render_hook("page_visibility", %{"hidden" => true})
    say(bob, room, "@#{me.user.username} while away")
    assert title(view) == "(1) ##{room}"

    view |> element("#chat") |> render_hook("page_visibility", %{"hidden" => false})
    assert title(view) == "##{room}"
  end
end
