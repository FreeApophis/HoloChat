defmodule HoloChatWeb.ChatHistoryTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.ChatFixtures

  @message_items "#messages > div[id^='messages-']:not(#messages-empty)"

  setup do
    %{scope: user_scope_fixture(), room: unique_room()}
  end

  test "shows the latest 50 messages and offers older ones", %{conn: conn} = context do
    post_messages(context, 55)
    {:ok, view, _html} = live(conn, ~p"/rooms/#{context.room}")

    assert message_bodies(view) == Enum.map(6..55, &"m#{&1}")
    assert has_element?(view, "#load-older")
    assert has_element?(view, "#messages[phx-viewport-top='load_older']")
    refute has_element?(view, "#history-start")
  end

  test "loads older messages above the current ones", %{conn: conn} = context do
    post_messages(context, 55)
    {:ok, view, _html} = live(conn, ~p"/rooms/#{context.room}")

    view |> element("#load-older") |> render_click()

    assert message_bodies(view) == Enum.map(1..55, &"m#{&1}")
  end

  test "marks the beginning of the room once everything is loaded", %{conn: conn} = context do
    post_messages(context, 55)
    {:ok, view, _html} = live(conn, ~p"/rooms/#{context.room}")

    view |> element("#load-older") |> render_click()

    refute has_element?(view, "#load-older")
    refute has_element?(view, "#messages[phx-viewport-top]")
    assert has_element?(view, "#history-start", context.room)
  end

  test "needs no paging when all messages fit", %{conn: conn} = context do
    post_messages(context, 3)
    {:ok, view, _html} = live(conn, ~p"/rooms/#{context.room}")

    refute has_element?(view, "#load-older")
    assert has_element?(view, "#history-start")
  end

  test "keeps new live messages at the bottom after loading history",
       %{conn: conn} = context do
    post_messages(context, 55)
    {:ok, view, _html} = live(conn, ~p"/rooms/#{context.room}")

    view |> element("#load-older") |> render_click()
    message_fixture(context.scope, context.room, %{"body" => "live"})

    assert List.last(message_bodies(view)) == "live"
    assert hd(message_bodies(view)) == "m1"
  end

  test "switching rooms starts paging afresh", %{conn: conn} = context do
    post_messages(context, 55)
    small = unique_room()
    message_fixture(context.scope, small, %{"body" => "only one"})
    {:ok, view, _html} = live(conn, ~p"/rooms/#{context.room}")

    # Patch directly: other async tests' activity can push these rooms out of
    # the 20-room sidebar, and the sidebar is not what this test is about.
    render_patch(view, ~p"/rooms/#{small}")

    assert message_bodies(view) == ["only one"]
    refute has_element?(view, "#load-older")

    render_patch(view, ~p"/rooms/#{context.room}")
    assert has_element?(view, "#load-older")
    assert length(message_bodies(view)) == 50
  end

  defp post_messages(%{scope: scope, room: room}, count) do
    for n <- 1..count, do: message_fixture(scope, room, %{"body" => "m#{n}"})
  end

  defp message_bodies(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(@message_items <> " p")
    |> Enum.map(&LazyHTML.text/1)
  end
end
