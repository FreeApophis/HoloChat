defmodule HoloChat.Assistant.Director do
  @moduledoc """
  Decides which cast characters answer in a scene. Pure functions; the
  server applies the decisions.

  Characters are named by their full, first or last name, with or without
  `@`.
  With the `"natural"` policy, the characters named in a message answer in
  the order they were named; if nobody is named, one character answers,
  picked at random but not the one who spoke last. With `"mention"`, only
  named characters answer.
  """

  @doc """
  Returns true if `text` names the character.
  """
  def named?(character, text), do: name_position(character, text) != nil

  @doc """
  Returns the characters that should answer `text`, at most `:limit`.

  Options: `:policy` (`"natural"`, the default, or `"mention"`), `:limit`,
  `:last_speaker_id` and `:random` (a function picking one element of a
  list, `Enum.random/1` by default).
  """
  def responders(cast, text, opts) do
    policy = Keyword.get(opts, :policy, "natural")
    limit = Keyword.get(opts, :limit, length(cast))

    case {named_in_order(cast, text), policy} do
      {[], "natural"} -> random_responder(cast, opts)
      {named, _policy} -> named
    end
    |> Enum.take(limit)
  end

  @doc """
  Returns the character, other than `speaker`, named first in `text`: who
  answers next when characters talk to each other. Nil if nobody is named.
  """
  def next_in_chain(cast, speaker, text) do
    cast
    |> Enum.reject(&(&1.id == speaker.id))
    |> named_in_order(text)
    |> List.first()
  end

  defp random_responder([], _opts), do: []

  defp random_responder(cast, opts) do
    random = Keyword.get(opts, :random, &Enum.random/1)
    last = Keyword.get(opts, :last_speaker_id)

    candidates =
      case Enum.reject(cast, &(&1.id == last)) do
        [] -> cast
        others -> others
      end

    [random.(candidates)]
  end

  defp named_in_order(cast, text) do
    cast
    |> Enum.map(&{name_position(&1, text), &1})
    |> Enum.reject(fn {position, _character} -> position == nil end)
    |> Enum.sort_by(fn {position, _character} -> position end)
    |> Enum.map(fn {_position, character} -> character end)
  end

  # Where the full, first or last name first appears as a whole word.
  defp name_position(%{name: name}, text) do
    parts = String.split(name)

    [name, List.first(parts), List.last(parts)]
    |> Enum.uniq()
    |> Enum.flat_map(fn candidate ->
      case Regex.run(~r/(?<![\w])#{Regex.escape(candidate)}(?![\w])/iu, text, return: :index) do
        [{position, _length}] -> [position]
        nil -> []
      end
    end)
    |> Enum.min(fn -> nil end)
  end
end
