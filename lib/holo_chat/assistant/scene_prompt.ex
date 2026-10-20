defmodule HoloChat.Assistant.ScenePrompt do
  @moduledoc """
  Builds the prompt for a cast character in a role-play scene, and turns
  the model's output into that character's message.

  The system prompt holds the scene (the room's scenario), the character's
  sheet and who else is present. Players appear by name only: their
  profile descriptions are never sent to the model. The history starts
  after the latest scenario change: the cast doesn't remember earlier
  scenarios.
  """

  alias HoloChat.Assistant

  @doc """
  Builds the chat completion messages for `character` in `room` with the
  scene's `cast` and recent `history` (oldest first).

  The character's own messages are assistant turns; everything else is
  merged into user turns of "Name: message" lines, which keeps turns
  alternating as strict chat templates require.

  `worn` maps character ids to the characters players wore when writing
  their messages: those players appear as their character, played by a
  human.
  """
  def build(room, character, cast, history, worn \\ %{}) do
    history =
      history
      |> since_scenario_change()
      |> Enum.map(&Map.put(&1, :speaker, speaker(&1, worn)))

    [
      %{role: "system", content: system_prompt(room, character, cast, history)}
      | turns(character, history)
    ]
  end

  # Who a message is from as the scene sees it, and their character, if a
  # player wore one.
  defp speaker(%{from_assistant: false, character_id: id, username: username}, worn)
       when is_integer(id) do
    case worn[id] do
      nil -> {username, nil}
      character -> {character.name, character}
    end
  end

  defp speaker(%{username: username}, _worn), do: {username, nil}

  defp system_prompt(room, character, cast, history) do
    name = character.name

    [
      "You are playing #{name} in a group role-play with several participants. " <>
        "Write only #{name}'s next message: what #{name} says and does, in character. " <>
        "Put actions in *asterisks*. Never write lines or actions for anyone else, " <>
        "and don't narrate the scene. Keep it to one or two short paragraphs.",
      scene(room.scenario),
      section(
        name,
        [
          character.description,
          labeled("Personality", character.personality),
          labeled("Example dialogue", character.example_dialogue)
        ]
      ),
      section("Others in the scene", others(character, cast, history))
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end

  defp scene(nil), do: nil
  defp scene(scenario), do: section("Scene: #{scenario.title}", scenario.description)

  defp since_scenario_change(history) do
    case Enum.find_index(Enum.reverse(history), &(&1.kind == "scenario")) do
      nil -> history
      from_end -> Enum.take(history, -from_end)
    end
  end

  defp others(character, cast, history) do
    characters =
      for other <- cast, other.id != character.id do
        "- #{other.name}" <> summary(other.description)
      end

    players =
      for %{persona_id: nil, from_assistant: false, speaker: speaker} <- history,
          uniq: true,
          do: player_line(speaker)

    characters ++ players
  end

  defp player_line({name, nil}), do: "- #{name} (a player)"

  defp player_line({name, character}) do
    "- #{name} (played by a human player)" <> summary(character.description)
  end

  # The first sentence of a description, so others are known but brief.
  defp summary(nil), do: ""

  defp summary(description) do
    case Regex.run(~r/\A.*?[.!?](?=\s|\z)/s, String.trim(description)) do
      [sentence] -> ": " <> sentence
      nil -> ": " <> String.slice(description, 0, 160)
    end
  end

  defp labeled(_label, blank) when blank in [nil, ""], do: nil
  defp labeled(label, text), do: "#{label}:\n#{text}"

  defp section(_title, blank) when blank in [nil, "", []], do: nil

  defp section(title, parts) when is_list(parts) do
    case Enum.reject(parts, &(&1 in [nil, ""])) do
      [] -> nil
      parts -> "# #{title}\n" <> Enum.join(parts, "\n")
    end
  end

  defp section(title, text), do: "# #{title}\n#{text}"

  defp turns(character, history) do
    history
    |> Enum.map(fn
      %{from_assistant: true, character_id: id, body: body} when id == character.id ->
        {"assistant", body}

      %{speaker: {name, _character}, body: body} ->
        {"user", Assistant.chat_line(name, body)}
    end)
    |> Enum.chunk_by(fn {role, _content} -> role end)
    |> Enum.map(fn [{role, _} | _] = chunk ->
      %{role: role, content: Enum.map_join(chunk, "\n", fn {_role, content} -> content end)}
    end)
    |> ensure_user_last()
  end

  defp ensure_user_last(turns) do
    case List.last(turns) do
      %{role: "user"} -> turns
      _assistant_or_none -> turns ++ [%{role: "user", content: "(The scene continues.)"}]
    end
  end

  @doc """
  Turns raw model output into the character's message: drops reasoning and
  a leading "Name:", and cuts the text where the model starts writing for
  one of `other_names`. Returns nil if nothing is left.
  """
  def clean(text, character, other_names) do
    with reply when is_binary(reply) <- Assistant.clean_reply(character.name, text) do
      reply |> cut_at_others(other_names) |> blank_to_nil()
    end
  end

  defp cut_at_others(reply, []), do: reply

  defp cut_at_others(reply, names) do
    alternatives = Enum.map_join(names, "|", &Regex.escape/1)
    [kept | _rest] = Regex.split(~r/^\s*(?:#{alternatives}):/imu, reply, parts: 2)
    String.trim(kept)
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text
end
