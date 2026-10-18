defmodule HoloChatWeb.ChatPresenceTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias HoloChatWeb.Presence
  alias Phoenix.Socket.Broadcast
  alias Phoenix.Tracker.Shard

  setup do
    # PubSub and Presence are global, so each test gets its own room.
    room = "presence-#{System.unique_integer([:positive])}"
    Presence.subscribe(room)

    on_exit(fn ->
      for pid <- Presence.fetchers_pids() do
        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, _, _, _}, 1000
      end
    end)

    %{room: room}
  end

  test "lists everyone in the room", %{conn: conn, room: room} do
    {:ok, ada, _html} = live(conn, ~p"/rooms/#{room}")
    {:ok, other, _html} = live(build_conn(), ~p"/rooms/#{room}")

    type(ada, "ada", "")
    await_presence(%{name: "ada", typing: false})

    assert has_element?(other, "#online-count", "2 online")
    assert has_element?(other, "#online-users[title='ada, 1 guest']")
  end

  test "shows others typing, but not yourself", %{conn: conn, room: room} do
    {:ok, ada, _html} = live(conn, ~p"/rooms/#{room}")
    {:ok, other, _html} = live(build_conn(), ~p"/rooms/#{room}")

    type(ada, "ada", "hel")
    await_presence(%{name: "ada", typing: true})

    assert has_element?(other, "#typing-indicator", "ada is typing")
    refute has_element?(ada, "#typing-indicator", "is typing")
  end

  test "typing stops when the message is sent", %{conn: conn, room: room} do
    {:ok, ada, _html} = live(conn, ~p"/rooms/#{room}")
    {:ok, other, _html} = live(build_conn(), ~p"/rooms/#{room}")

    type(ada, "ada", "hello")
    await_presence(%{name: "ada", typing: true})

    ada
    |> form("#message-form", message: %{username: "ada", body: "hello"})
    |> render_submit()

    await_presence(%{name: "ada", typing: false})
    refute has_element?(other, "#typing-indicator", "is typing")
  end

  test "typing stops when the body is cleared", %{conn: conn, room: room} do
    {:ok, ada, _html} = live(conn, ~p"/rooms/#{room}")
    {:ok, other, _html} = live(build_conn(), ~p"/rooms/#{room}")

    type(ada, "ada", "hello")
    await_presence(%{name: "ada", typing: true})
    type(ada, "ada", "")
    await_presence(%{name: "ada", typing: false})

    refute has_element?(other, "#typing-indicator", "is typing")
  end

  test "typing stops after the idle timeout", %{conn: conn, room: room} do
    {:ok, ada, _html} = live(conn, ~p"/rooms/#{room}")
    {:ok, other, _html} = live(build_conn(), ~p"/rooms/#{room}")

    type(ada, "ada", "hello")
    await_presence(%{name: "ada", typing: true})

    # Simulate the timer firing instead of waiting for it.
    send(ada.pid, :typing_timeout)
    await_presence(%{name: "ada", typing: false})

    refute has_element?(other, "#typing-indicator", "is typing")
  end

  test "several typists are summarized", %{room: room} do
    views =
      for name <- ~w(ada bob cy) do
        {:ok, view, _html} = live(build_conn(), ~p"/rooms/#{room}")
        {name, view}
      end

    {:ok, watcher, _html} = live(build_conn(), ~p"/rooms/#{room}")

    for {name, view} <- views do
      type(view, name, "hi")
      await_presence(%{name: name, typing: true})
    end

    assert has_element?(watcher, "#typing-indicator", "Several people are typing")
  end

  defp type(view, username, body) do
    view
    |> form("#message-form", message: %{username: username, body: body})
    |> render_change()
  end

  # Waits for a presence_diff that carries `expected` metadata. Once the
  # tracker shard has finished broadcasting it, every LiveView in the room
  # has the diff in its mailbox, so the next render reflects it.
  defp await_presence(expected) do
    receive do
      %Broadcast{event: "presence_diff", payload: %{joins: joins}} ->
        if Enum.any?(joins, fn {_key, %{metas: metas}} ->
             Enum.any?(metas, &matches?(&1, expected))
           end) do
          :sys.get_state(Shard.name_for_number(Presence, 0))
          :ok
        else
          await_presence(expected)
        end
    after
      1000 -> flunk("no presence_diff with #{inspect(expected)}")
    end
  end

  defp matches?(meta, expected), do: Map.take(meta, Map.keys(expected)) == expected
end
