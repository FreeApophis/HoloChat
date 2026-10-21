defmodule HoloChat.Assistant.ScenePrompt do
  @moduledoc """
  Builds the prompt for a cast character in a role-play scene, and turns
  the model's output into that character's message.

  The system prompt holds the scene (the room's scenario), the character's
  sheet and who else is present. Players appear by name only: their
  profile descriptions are never sent to the model. The history starts
  after the latest scenario change: the cast doesn't remember earlier
  scenarios.

  The system prompt is written from a template (see
  `HoloChat.Assistant.PromptTemplate`) with these placeholders:

    * `{{char}}`: the character's name
    * `{{description}}`, `{{personality}}`: the character's sheet
    * `{{scenario_title}}`, `{{scenario}}`: the room's scenario
    * `{{others}}`: who else is in the scene, one "- Name: ..." line each

  A line whose placeholders are all empty is left out, and so is a
  paragraph that loses all of its placeholder lines, so a "Personality:"
  label disappears with an empty personality.
  """

  alias HoloChat.Assistant

  # The built-in Standard template of each room language (see
  # HoloChat.Rooms.languages/0), and the words the prompt adds itself.
  @default_templates %{
    "en" => """
    You are playing {{char}} in a group role-play with several participants. \
    Write only {{char}}'s next message: what {{char}} says and does, in character. \
    Put actions in *asterisks*. Never write lines or actions for anyone else, \
    and don't narrate the scene. Keep it to one or two short paragraphs.

    # Scene: {{scenario_title}}
    {{scenario}}

    # {{char}}
    {{description}}

    Personality:
    {{personality}}

    # Others in the scene
    {{others}}
    """,
    "de" => """
    Du spielst {{char}} in einem Gruppen-Rollenspiel mit mehreren Teilnehmenden. \
    Schreibe nur die nächste Nachricht von {{char}}: was {{char}} sagt und tut, \
    ganz in der Rolle. Setze Handlungen in *Sternchen*. Schreibe nie Zeilen oder \
    Handlungen für andere und erzähle die Szene nicht. Halte dich an ein oder zwei \
    kurze Absätze. Schreibe auf Deutsch.

    # Szene: {{scenario_title}}
    {{scenario}}

    # {{char}}
    {{description}}

    Persönlichkeit:
    {{personality}}

    # Weitere Anwesende
    {{others}}
    """
  }

  @words %{
    "en" => %{
      player: "a player",
      human: "played by a human player",
      continues: "(The scene continues.)"
    },
    "de" => %{
      player: "Spieler",
      human: "gespielt von einem Menschen",
      continues: "(Die Szene geht weiter.)"
    }
  }

  @placeholders ~w(char description personality scenario_title scenario others)

  @doc """
  The built-in Standard template in `language`, used by rooms that chose
  none.
  """
  def default_template(language \\ "en"), do: Map.fetch!(@default_templates, language)

  @doc """
  Builds the chat completion messages for `character` in `room` with the
  scene's `cast` and recent `history` (oldest first), with the system
  prompt written from `template` (the Standard one of the room's language
  when nil). The words the prompt adds itself follow the room's language.

  The character's own messages are assistant turns; everything else is
  merged into user turns of "Name: message" lines, which keeps turns
  alternating as strict chat templates require.

  `worn` maps character ids to the characters players wore when writing
  their messages: those players appear as their character, played by a
  human.
  """
  def build(room, character, cast, history, worn \\ %{}, template \\ nil) do
    language = room.language || "en"
    words = Map.fetch!(@words, language)

    history =
      history
      |> since_scenario_change()
      |> Enum.map(&Map.put(&1, :speaker, speaker(&1, worn)))

    template = template || default_template(language)

    [
      %{role: "system", content: system_prompt(template, room, character, cast, history, words)}
      | turns(character, history, words)
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

  defp system_prompt(template, room, character, cast, history, words) do
    scenario = room.scenario || %{title: nil, description: nil}

    values = %{
      "char" => character.name,
      "description" => character.description,
      "personality" => character.personality,
      "scenario_title" => scenario.title,
      "scenario" => scenario.description,
      "others" => Enum.join(others(character, cast, history, words), "\n")
    }

    render(template, values)
  end

  defp render(template, values) do
    template
    |> String.split(~r/\n\s*\n/)
    |> Enum.flat_map(&render_paragraph(&1, values))
    |> Enum.join("\n\n")
    |> String.trim()
  end

  # Nothing if the paragraph had placeholder lines and lost them all.
  defp render_paragraph(paragraph, values) do
    lines = paragraph |> String.split("\n") |> Enum.map(&render_line(&1, values))

    if :dropped in lines and not Enum.any?(lines, &match?({:filled, _text}, &1)) do
      []
    else
      [Enum.map_join(for({_kind, text} <- lines, do: text), "\n", & &1)]
    end
  end

  # {:static, text} without placeholders, {:filled, text} with at least one
  # filled in, :dropped when all of them are empty.
  defp render_line(line, values) do
    names = Regex.scan(placeholder_regex(), line, capture: :all_but_first)

    cond do
      names == [] ->
        {:static, line}

      Enum.all?(names, fn [name] -> blank?(values[name]) end) ->
        :dropped

      true ->
        {:filled,
         Regex.replace(placeholder_regex(), line, fn _match, name -> values[name] || "" end)}
    end
  end

  defp placeholder_regex, do: ~r/\{\{(#{Enum.join(@placeholders, "|")})\}\}/

  defp blank?(value), do: value in [nil, ""] or String.trim(value) == ""

  defp since_scenario_change(history) do
    case Enum.find_index(Enum.reverse(history), &(&1.kind == "scenario")) do
      nil -> history
      from_end -> Enum.take(history, -from_end)
    end
  end

  defp others(character, cast, history, words) do
    characters =
      for other <- cast, other.id != character.id do
        "- #{other.name}" <> summary(other.description)
      end

    players =
      for %{persona_id: nil, from_assistant: false, speaker: speaker} <- history,
          uniq: true,
          do: player_line(speaker, words)

    characters ++ players
  end

  defp player_line({name, nil}, words), do: "- #{name} (#{words.player})"

  defp player_line({name, character}, words) do
    "- #{name} (#{words.human})" <> summary(character.description)
  end

  # The first sentence of a description, so others are known but brief.
  defp summary(nil), do: ""

  defp summary(description) do
    case Regex.run(~r/\A.*?[.!?](?=\s|\z)/s, String.trim(description)) do
      [sentence] -> ": " <> sentence
      nil -> ": " <> String.slice(description, 0, 160)
    end
  end

  defp turns(character, history, words) do
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
    |> ensure_user_last(words)
  end

  defp ensure_user_last(turns, words) do
    case List.last(turns) do
      %{role: "user"} -> turns
      _assistant_or_none -> turns ++ [%{role: "user", content: words.continues}]
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
