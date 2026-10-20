defmodule HoloChat.Cards do
  @moduledoc """
  Imports SillyTavern character cards.

  A card mixes a character with the scene it plays in. HoloChat keeps the
  two apart, so a card is split into a draft for the character library and
  a draft for the scenario library (the card's scenario and first message).
  The importer reviews both before `import_card/4` creates them, with the
  character in the scenario's cast.

  Cards come as PNG images with the card in a base64 JSON `tEXt` chunk
  (`ccv3` for V3, `chara` for V1 and V2), or as plain JSON. Placeholders are
  filled in: `{{char}}` with the character's name, `{{user}}` with "the
  player", since a room has many players.
  """

  use Boundary,
    deps: [HoloChat.Repo, HoloChat.Accounts, HoloChat.Characters, HoloChat.Scenarios]

  alias HoloChat.Accounts.{Scope, User}
  alias HoloChat.{Characters, Scenarios}
  alias HoloChat.Repo

  @png_signature <<137, 80, 78, 71, 13, 10, 26, 10>>

  @doc """
  Reads a card from a PNG or JSON file.

  Returns `{:ok, %{character: params, scenario: params | nil, image: png | nil}}`,
  where the params are string-keyed form params for `Characters` and
  `Scenarios`, or `{:error, :invalid_card}`.
  """
  def read(binary) when is_binary(binary) do
    with {:ok, json, image} <- extract(binary),
         {:ok, card} <- Jason.decode(json),
         %{"name" => name} = fields when is_binary(name) <- card_fields(card),
         name when name != "" <- String.trim(name) do
      {:ok, draft(fields, name, image)}
    else
      _invalid -> {:error, :invalid_card}
    end
  end

  defp extract(@png_signature <> chunks) do
    text = text_chunks(chunks, %{})

    with {:ok, encoded} <- Map.fetch(text, "ccv3") |> or_fetch(text, "chara"),
         {:ok, json} <- Base.decode64(encoded, ignore: :whitespace) do
      {:ok, json, @png_signature <> chunks}
    end
  end

  defp extract(json), do: {:ok, json, nil}

  defp or_fetch(:error, map, key), do: Map.fetch(map, key)
  defp or_fetch(found, _map, _key), do: found

  defp text_chunks(<<length::32, "tEXt", data::binary-size(length), _crc::32, rest::binary>>, acc) do
    acc =
      case :binary.split(data, <<0>>) do
        [keyword, text] -> Map.put(acc, String.downcase(keyword), text)
        _malformed -> acc
      end

    text_chunks(rest, acc)
  end

  defp text_chunks(<<_length::32, "IEND", _rest::binary>>, acc), do: acc

  defp text_chunks(
         <<length::32, _type::binary-4, _data::binary-size(length), _crc::32, rest::binary>>,
         acc
       ),
       do: text_chunks(rest, acc)

  defp text_chunks(_truncated, acc), do: acc

  # V2 and V3 cards keep their fields under "data"; V1 cards at the top.
  defp card_fields(%{"data" => %{} = data}), do: data
  defp card_fields(%{} = card), do: card
  defp card_fields(_other), do: nil

  defp draft(fields, name, image) do
    text = fn key -> fields |> text(key) |> fill(name) end
    tag_list = fields |> Map.get("tags") |> tag_list()

    character = %{
      "name" => name,
      "description" => text.("description"),
      "personality" => text.("personality"),
      "example_dialogue" => fields |> text("mes_example") |> dialogue() |> fill(name),
      "tag_list" => tag_list
    }

    scene =
      [text.("scenario"), text.("first_mes")]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n\n")

    scenario =
      if scene != "" do
        %{
          "title" => String.slice("#{name}'s story", 0, 60),
          "description" => scene,
          "tag_list" => tag_list
        }
      end

    %{character: character, scenario: scenario, image: image}
  end

  defp text(fields, key) do
    case Map.get(fields, key) do
      value when is_binary(value) -> value |> String.replace("\r\n", "\n") |> String.trim()
      _missing -> ""
    end
  end

  defp tag_list(tags) when is_list(tags),
    do: tags |> Enum.filter(&is_binary/1) |> Enum.join(", ")

  defp tag_list(_tags), do: ""

  # Example chats are separated by <START> lines; the player's lines are
  # labelled "Player".
  defp dialogue(text) do
    text
    |> String.split(~r/^\s*<START>\s*$/mi)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
    |> String.replace(~r/^(?:\{\{user\}\}|<USER>):/mi, "Player:")
  end

  defp fill(text, name) do
    text
    |> String.replace(~r/\{\{char\}\}|<BOT>/i, name)
    |> String.replace(~r/(^|[.!?]\s+)(?:\{\{user\}\}|<USER>)/mi, "\\1The player")
    |> String.replace(~r/\{\{user\}\}|<USER>/i, "the player")
  end

  @doc """
  Creates a character from `character_params` with `image` (or none) as
  its avatar and, unless `scenario_params` is nil, a scenario casting it,
  both owned by the scope's user. Nothing is created if anything fails.

  Returns `{:ok, %{character: character, scenario: scenario | nil}}`, or
  `{:error, changeset | :invalid_image | :unauthorized}`.
  """
  def import_card(%Scope{user: %User{}} = scope, character_params, scenario_params, image) do
    Repo.transact(fn ->
      with {:ok, character} <- Characters.create_character(scope, character_params),
           {:ok, character} <- put_avatar(scope, character, image),
           {:ok, scenario} <- create_scenario(scope, scenario_params, character) do
        {:ok, %{character: character, scenario: scenario}}
      end
    end)
  end

  def import_card(_scope, _character_params, _scenario_params, _image),
    do: {:error, :unauthorized}

  defp put_avatar(_scope, character, nil), do: {:ok, character}

  defp put_avatar(scope, character, image),
    do: Characters.update_character_avatar(scope, character, image)

  defp create_scenario(_scope, nil, _character), do: {:ok, nil}

  defp create_scenario(scope, params, character) do
    with {:ok, scenario} <- Scenarios.create_scenario(scope, params) do
      Scenarios.cast_character(scope, scenario, character.id)
    end
  end
end
