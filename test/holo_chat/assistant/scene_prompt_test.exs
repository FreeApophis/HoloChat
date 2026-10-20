defmodule HoloChat.Assistant.ScenePromptTest do
  use ExUnit.Case, async: true

  alias HoloChat.Assistant.ScenePrompt
  alias HoloChat.Characters.Character
  alias HoloChat.Chat.Message
  alias HoloChat.Rooms.Room
  alias HoloChat.Scenarios.Scenario

  @room %Room{scenario: %Scenario{title: "Tea at the Burrow", description: "A rainy afternoon."}}
  @luna %Character{
    id: 1,
    name: "Luna",
    description: "Dreamy Ravenclaw.",
    personality: "Calm."
  }
  @neville %Character{id: 2, name: "Neville", description: "Shy. Loves plants. Brave."}

  defp human(name, body), do: %Message{username: name, body: body, user_id: 9}

  defp character(char, body),
    do: %Message{username: char.name, body: body, character_id: char.id, from_assistant: true}

  describe "build/4" do
    test "puts the scene, the character sheet and the others in the system prompt" do
      [system | _] = ScenePrompt.build(@room, @luna, [@luna, @neville], [human("ada", "Hi")])

      assert system.role == "system"
      assert system.content =~ "You are playing Luna"
      assert system.content =~ "A rainy afternoon."
      assert system.content =~ "Dreamy Ravenclaw."
      assert system.content =~ "Calm."
      refute system.content =~ "Example dialogue"
      assert system.content =~ "Neville"
      assert system.content =~ "ada"
    end

    test "makes the character's own messages assistant turns and merges the rest" do
      history = [
        human("ada", "Hi"),
        character(@neville, "Hello."),
        character(@luna, "Hello, everyone."),
        human("bob", "Tea?")
      ]

      [_system | turns] = ScenePrompt.build(@room, @luna, [@luna, @neville], history)

      assert turns == [
               %{role: "user", content: "ada: Hi\nNeville: Hello."},
               %{role: "assistant", content: "Hello, everyone."},
               %{role: "user", content: "bob: Tea?"}
             ]
    end

    test "leaves out everything before the latest scenario change" do
      history = [
        human("ada", "In the old scene"),
        %Message{username: "gm", body: "Tea at the Burrow", kind: "scenario", user_id: 8},
        human("bob", "In the new scene")
      ]

      [system | turns] = ScenePrompt.build(@room, @luna, [@luna], history)

      assert turns == [%{role: "user", content: "bob: In the new scene"}]
      refute system.content =~ "ada"
      refute system.content =~ "gm (a player)"
    end

    test "writes /me actions as actions" do
      [_system | turns] = ScenePrompt.build(@room, @luna, [@luna], [human("ada", "/me waves")])

      assert turns == [%{role: "user", content: "*ada waves*"}]
    end

    test "shows players by the character they wear, played by a human" do
      riker = %Character{id: 3, name: "Riker", description: "First officer. Tall."}
      history = [%Message{username: "ada", body: "Hello.", user_id: 9, character_id: riker.id}]

      [system | turns] = ScenePrompt.build(@room, @luna, [@luna], history, %{riker.id => riker})

      assert system.content =~ "- Riker (played by a human player): First officer."
      refute system.content =~ "ada"
      assert turns == [%{role: "user", content: "Riker: Hello."}]
    end

    test "only the model's own messages are the character's turns" do
      # A player once wore Luna; that was not the model speaking.
      history = [%Message{username: "ada", body: "As Luna.", user_id: 9, character_id: @luna.id}]

      [_system | turns] = ScenePrompt.build(@room, @luna, [@luna], history, %{@luna.id => @luna})

      assert turns == [%{role: "user", content: "Luna: As Luna."}]
    end

    test "never ends on the character's own turn" do
      [_system | turns] = ScenePrompt.build(@room, @luna, [@luna], [character(@luna, "Hm.")])

      assert List.last(turns).role == "user"
    end
  end

  describe "clean/3" do
    test "drops a leading name and stops where the model writes for someone else" do
      text = "Luna: *looks up* Oh, hello.\nNeville: Hi Luna!\nLuna: More."

      assert ScenePrompt.clean(text, @luna, ["Neville", "ada"]) == "*looks up* Oh, hello."
    end

    test "returns nil when nothing is left" do
      assert ScenePrompt.clean("<think>hm</think>  ", @luna, []) == nil
      assert ScenePrompt.clean("ada: hi", @luna, ["ada"]) == nil
    end
  end
end
