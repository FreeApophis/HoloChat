defmodule HoloChatWeb.SceneRepliesTest do
  # Runs the real assistant server, which needs the shared sandbox and Mox mode.
  use HoloChatWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.RoomsFixtures
  import HoloChat.ScenariosFixtures
  import HoloChatWeb.PresenceHelpers

  alias HoloChat.{Accounts, Assistant, Chat, Rooms, Scenarios}
  alias HoloChat.Assistant.{LLMMock, Server}
  alias HoloChatWeb.Presence

  setup :set_mox_global
  setup :verify_on_exit!

  setup do
    {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
    {:ok, _} = Assistant.update_settings(user_scope_fixture(admin), %{"enabled" => "true"})

    gm = user_scope_fixture()
    # No waiting in tests: the cast answers as soon as a player has posted.
    room = roleplay_room_fixture(gm, %{"description" => "A tea party in the Burrow."})
    {:ok, room} = Rooms.update_room(gm, room, %{"reply_delay" => "0"})

    luna =
      character_fixture(gm, %{"name" => "Luna Lovegood", "description" => "Dreamy Ravenclaw."})

    {:ok, _} = Rooms.cast_character(gm, room, luna.id)

    Chat.subscribe(room.name)
    Presence.subscribe(room.name)
    on_exit(&await_presence_fetchers/0)

    %{gm: gm, room: room, luna: luna}
  end

  defp start_server, do: start_supervised!({Server, name: nil})

  defp join(room) do
    player = user_fixture()

    {:ok, view, _html} =
      build_conn_with_unique_ip() |> log_in_user(player) |> live(~p"/rooms/#{room.name}")

    {player, view}
  end

  test "a cast character answers a player in character", %{room: room, luna: luna} do
    start_server()
    await_presence(%{name: "Luna Lovegood"})
    {player, view} = join(room)

    expect(LLMMock, :chat, fn _url, messages, _opts ->
      system = hd(messages).content
      assert system =~ "Luna Lovegood"
      assert system =~ "A tea party in the Burrow."
      assert system =~ "Dreamy Ravenclaw."
      assert List.last(messages).content == "#{player.username}: Good evening!"
      {:ok, "Luna Lovegood: *smiles* Have you seen any Nargles?"}
    end)

    view |> form("#message-form", message: %{body: "Good evening!"}) |> render_submit()

    assert_receive {:new_message, %{from_assistant: true, character_id: id, body: body} = reply},
                   1000

    assert id == luna.id
    assert body == "*smiles* Have you seen any Nargles?"

    assert has_element?(view, "#messages-#{reply.id} [data-role='author']", "Luna Lovegood")
    assert has_element?(view, "#messages-#{reply.id} [data-role='assistant-badge']")

    view |> element("#messages-#{reply.id} [data-role='author']") |> render_click()
    assert has_element?(view, "#profile-card", "Dreamy Ravenclaw.")
  end

  test "the character named in a message answers", %{gm: gm, room: room} do
    neville = character_fixture(gm, %{"name" => "Neville Longbottom"})
    {:ok, _} = Rooms.cast_character(gm, room, neville.id)
    start_server()
    {_player, view} = join(room)

    expect(LLMMock, :chat, fn _url, messages, _opts ->
      assert hd(messages).content =~ "You are playing Neville Longbottom"
      {:ok, "Oh! Me?"}
    end)

    view
    |> form("#message-form", message: %{body: "What do you think, Neville?"})
    |> render_submit()

    assert_receive {:new_message, %{character_id: id, username: "Neville Longbottom"}}, 1000
    assert id == neville.id
  end

  test "characters answer each other up to the scene's turn limit", %{gm: gm, room: room} do
    neville = character_fixture(gm, %{"name" => "Neville Longbottom"})
    {:ok, _} = Rooms.cast_character(gm, room, neville.id)
    {:ok, _} = Rooms.update_room(gm, room, %{"max_ai_turns" => "2"})
    start_server()
    {_player, view} = join(room)

    # Luna is named and answers, naming Neville, who answers and names Luna;
    # the turn limit of two stops Luna from answering again.
    expect(LLMMock, :chat, 2, fn _url, messages, _opts ->
      if hd(messages).content =~ "You are playing Luna",
        do: {:ok, "Neville, tell them about your plants."},
        else: {:ok, "Well, Luna, the Mimbulus mimbletonia is lovely."}
    end)

    view |> form("#message-form", message: %{body: "Hello Luna!"}) |> render_submit()

    assert_receive {:new_message, %{username: "Luna Lovegood"}}, 1000
    assert_receive {:new_message, %{username: "Neville Longbottom"}}, 1000
    refute_receive {:new_message, %{from_assistant: true}}, 300
  end

  test "with 'only when named', unnamed messages get no reply", %{gm: gm, room: room} do
    {:ok, _} = Rooms.update_room(gm, room, %{"reply_policy" => "mention"})
    start_server()
    {_player, view} = join(room)

    view |> form("#message-form", message: %{body: "Nice weather."}) |> render_submit()
    refute_receive {:new_message, %{from_assistant: true}}, 300

    expect(LLMMock, :chat, fn _url, _messages, _opts -> {:ok, "It is, isn't it?"} end)
    view |> form("#message-form", message: %{body: "Right, Luna?"}) |> render_submit()

    assert_receive {:new_message, %{username: "Luna Lovegood"}}, 1000
  end

  test "the cast is online and shown typing", %{room: room, luna: luna} do
    start_server()
    await_presence(%{name: "Luna Lovegood", typing: false})
    {_player, view} = join(room)
    assert has_element?(view, "#online-users [data-character-id='#{luna.id}']")

    test = self()

    expect(LLMMock, :chat, fn _url, _messages, _opts ->
      send(test, {:generating, self()})

      receive do
        :continue -> {:ok, "Hello."}
      end
    end)

    view |> form("#message-form", message: %{body: "Hi"}) |> render_submit()
    assert_receive {:generating, llm}, 1000
    await_presence(%{name: "Luna Lovegood", typing: true})
    assert has_element?(view, "#typing-indicator", "Luna Lovegood is typing")

    send(llm, :continue)
    assert_receive {:new_message, %{from_assistant: true}}, 1000
  end

  test "the cast only remembers what happened since the scenario changed",
       %{gm: gm, room: room, luna: luna} do
    {:ok, _} =
      Chat.create_message(user_scope_fixture(), room.name, %{"body" => "Back at the Burrow"})

    garden =
      scenario_fixture(gm, %{"title" => "The garden", "description" => "Gnomes, everywhere."})

    {:ok, _} = Scenarios.cast_character(gm, garden, luna.id)
    {:ok, _} = Rooms.switch_scenario(gm, room, garden.id)

    start_server()
    {_player, view} = join(room)

    expect(LLMMock, :chat, fn _url, messages, _opts ->
      prompt = Enum.map_join(messages, "\n", & &1.content)
      assert prompt =~ "Gnomes, everywhere."
      refute prompt =~ "Back at the Burrow"
      refute prompt =~ "A tea party in the Burrow."
      {:ok, "*chases a gnome*"}
    end)

    view |> form("#message-form", message: %{body: "Where are we?"}) |> render_submit()

    assert_receive {:new_message, %{username: "Luna Lovegood"}}, 1000
  end

  test "a scenario change is no player turn for the cast", %{gm: gm, room: room, luna: luna} do
    garden = scenario_fixture(gm, %{"title" => "The garden"})
    {:ok, _} = Scenarios.cast_character(gm, garden, luna.id)
    start_server()
    await_presence(%{name: "Luna Lovegood"})

    test = self()

    stub(LLMMock, :chat, fn _url, _messages, _opts ->
      send(test, :llm_called)
      {:ok, "Hm."}
    end)

    {:ok, _} = Rooms.switch_scenario(gm, room, garden.id)

    assert_receive {:new_message, %{kind: "scenario"}}
    refute_receive :llm_called, 300
  end

  test "game masters choose how the cast takes turns", %{room: room} do
    conn = build_conn_with_unique_ip() |> log_in_user(gm_user(room))
    {:ok, view, _html} = live(conn, ~p"/rooms/#{room.name}/settings")

    view
    |> form("#scene-form",
      room: %{reply_policy: "mention", reply_delay: "10", max_ai_turns: "3"}
    )
    |> render_submit()

    assert %{reply_policy: "mention", reply_delay: 10, max_ai_turns: 3} =
             Rooms.get_room(room.name)
  end

  defp gm_user(room) do
    [master] = Rooms.list_game_masters(room)
    Accounts.get_user!(master.id)
  end
end
