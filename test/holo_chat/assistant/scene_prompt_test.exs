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

  describe "build/6 with a template" do
    test "fills in the placeholders" do
      template = """
      Play {{char}}. {{description}} {{personality}}

      # {{scenario_title}}
      {{scenario}}

      # With you
      {{others}}
      """

      [system | _] =
        ScenePrompt.build(@room, @luna, [@luna, @neville], [human("ada", "Hi")], %{}, template)

      assert system.content ==
               String.trim("""
               Play Luna. Dreamy Ravenclaw. Calm.

               # Tea at the Burrow
               A rainy afternoon.

               # With you
               - Neville: Shy.
               - ada (a player)
               """)
    end

    test "leaves out lines, and paragraphs, whose placeholders are all empty" do
      template =
        "Play {{char}}.\n{{description}}\n\nPersonality:\n{{personality}}\n\n" <>
          "# Scene\n{{scenario}}\n\nEnd."

      plain = %{@luna | personality: nil, description: nil}

      [system | _] = ScenePrompt.build(%Room{scenario: nil}, plain, [plain], [], %{}, template)

      assert system.content == "Play Luna.\n\nEnd."
    end

    test "keeps unknown placeholders and doesn't fill in placeholders from values" do
      sneaky = %{@luna | description: "Says {{others}}."}

      [system | _] =
        ScenePrompt.build(@room, sneaky, [sneaky], [], %{}, "{{description}} {{user}}")

      assert system.content == "Says {{others}}. {{user}}"
    end

    test "without a template, uses the built-in one" do
      history = [human("ada", "Hi")]

      assert ScenePrompt.build(@room, @luna, [@luna], history, %{}, nil) ==
               ScenePrompt.build(
                 @room,
                 @luna,
                 [@luna],
                 history,
                 %{},
                 ScenePrompt.default_template()
               )
    end
  end

  describe "build/6 in a German room" do
    test "uses the German Standard template and German labels" do
      room = %{@room | language: "de"}
      riker = %Character{id: 3, name: "Riker", description: "Erster Offizier."}

      history = [
        human("ada", "Hallo"),
        %Message{username: "bob", body: "Hi.", user_id: 8, character_id: riker.id},
        character(@luna, "Hallo zusammen.")
      ]

      [system | turns] = ScenePrompt.build(room, @luna, [@luna], history, %{riker.id => riker})

      assert system.content =~ "Du spielst Luna"
      assert system.content =~ "Persönlichkeit:"
      assert system.content =~ "- ada (Spieler)"
      assert system.content =~ "- Riker (gespielt von einem Menschen): Erster Offizier."
      assert List.last(turns) == %{role: "user", content: "(Die Szene geht weiter.)"}
    end

    test "each language has its own Standard template" do
      assert ScenePrompt.default_template("en") == ScenePrompt.default_template()
      assert ScenePrompt.default_template("de") =~ "Du spielst {{char}}"
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
