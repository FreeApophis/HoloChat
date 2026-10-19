defmodule HoloChat.Assistant.ScenePromptTest do
  use ExUnit.Case, async: true

  alias HoloChat.Assistant.ScenePrompt
  alias HoloChat.Characters.Character
  alias HoloChat.Chat.Message
  alias HoloChat.Rooms.Room

  @room %Room{title: "Tea at the Burrow", scenario: "A rainy afternoon."}
  @luna %Character{
    id: 1,
    name: "Luna",
    description: "Dreamy Ravenclaw.",
    personality: "Calm.",
    example_dialogue: "Luna: Nargles."
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
      assert system.content =~ "Luna: Nargles."
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
