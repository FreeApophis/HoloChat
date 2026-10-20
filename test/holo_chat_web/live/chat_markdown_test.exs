defmodule HoloChatWeb.ChatMarkdownTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures

  alias HoloChat.{Accounts, Chat}

  describe "messages" do
    test "render Markdown", %{conn: conn} do
      room = unique_room()

      message =
        message_fixture(user_scope_fixture(), room, %{
          "body" => "*waves* **Hello** `iex`\n- one\n- two"
        })

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      body = "#messages-#{message.id} [data-role='message-body']"
      assert has_element?(view, "#{body} em", "waves")
      assert has_element?(view, "#{body} strong", "Hello")
      assert has_element?(view, "#{body} code", "iex")
      assert has_element?(view, "#{body} li", "two")
    end

    test "link #room names to the room, switching inside the chat", %{conn: conn} do
      room = unique_room()
      other = unique_room()

      message =
        message_fixture(user_scope_fixture(), room, %{
          "body" => "Come to ##{other}! Not `##{room}` though."
        })

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      body = "#messages-#{message.id} [data-role='message-body']"
      assert has_element?(view, "#{body} a[href='/rooms/#{other}']", "##{other}")
      refute has_element?(view, "#{body} code a")

      view |> element("#{body} a[href='/rooms/#{other}']") |> render_click()

      assert_patch(view, ~p"/rooms/#{other}")
      assert has_element?(view, "#room-title", other)
    end

    test "show /me messages as actions of their author", %{conn: conn} do
      room = unique_room()
      author = user_scope_fixture()
      message = message_fixture(author, room, %{"body" => "/me waves *happily*"})

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      action = "#messages-#{message.id} [data-role='message-body'][data-action]"
      assert has_element?(view, action, author.user.username)
      assert has_element?(view, "#{action} em", "happily")
      refute has_element?(view, "#messages-#{message.id}", "/me")
    end

    test "hide ||spoilers|| until clicked", %{conn: conn} do
      room = unique_room()
      message = message_fixture(user_scope_fixture(), room, %{"body" => "The butler ||did it||."})

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      assert has_element?(
               view,
               "#messages-#{message.id} [data-role='message-body'] [data-role='spoiler'][phx-click]",
               "did it"
             )
    end

    test "render character replies as Markdown too", %{conn: conn} do
      room = unique_room()
      {:ok, reply} = Chat.create_assistant_message(room, "Sage", "*nods slowly*")

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      assert has_element?(view, "#messages-#{reply.id} [data-role='message-body'] em", "nods")
    end

    test "show HTML as text instead of running it", %{conn: conn} do
      room = unique_room()

      message =
        message_fixture(user_scope_fixture(), room, %{
          "body" =>
            "<script>alert(1)</script> <img src=x onerror=alert(2)> [x](javascript:alert(3))"
        })

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      body = "#messages-#{message.id} [data-role='message-body']"
      assert has_element?(view, body, "<script>alert(1)</script>")
      refute has_element?(view, "#{body} script")
      refute has_element?(view, "#{body} img")
      refute has_element?(view, "#{body} a")
    end

    test "open links in a new tab", %{conn: conn} do
      room = unique_room()

      message =
        message_fixture(user_scope_fixture(), room, %{"body" => "See https://example.com"})

      {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")

      assert has_element?(
               view,
               "#messages-#{message.id} a[href='https://example.com'][target='_blank'][rel*='noopener']"
             )
    end
  end

  test "scenarios render Markdown", %{conn: conn} do
    room = roleplay_room_fixture(user_scope_fixture(), %{"description" => "A **storm** rages."})

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}")
    view |> element("#show-scenario") |> render_click()

    assert has_element?(view, "#scenario strong", "storm")
  end

  test "profile descriptions render Markdown", %{conn: conn} do
    room = unique_room()
    {:ok, ada} = Accounts.update_user_profile(user_fixture(), %{"description" => "*Stargazer*"})
    message = message_fixture(user_scope_fixture(ada), room)

    {:ok, view, _html} = live(conn, ~p"/rooms/#{room}")
    view |> element("#messages-#{message.id} [data-role='author']") |> render_click()

    assert has_element?(view, "#profile-card em", "Stargazer")
  end

  test "character sheets render Markdown", %{conn: conn} do
    character =
      character_fixture(user_scope_fixture(), %{
        "description" => "A *dreamy* Ravenclaw.",
        "personality" => "**Calm**"
      })

    {:ok, view, _html} = live(conn, ~p"/characters/#{character.id}")

    assert has_element?(view, "#character-description em", "dreamy")
    assert has_element?(view, "#character-personality strong", "Calm")
  end
end
