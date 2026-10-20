defmodule HoloChatWeb.ChatMentionsTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures

  alias HoloChat.Rooms

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
