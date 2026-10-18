defmodule HoloChat.Assistant.Persona do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias HoloChat.Chat

  @default_system_prompt """
  You are {name}, a friendly AI assistant in HoloChat, a group chat.
  Messages from others are prefixed with their name. Reply in the language
  you were addressed in, keep answers short and conversational, and do not
  prefix your reply with your own name.
  """

  # An assistant identity, answering to @name in its rooms.
  schema "assistant_personas" do
    field :name, :string
    field :system_prompt, :string, default: String.trim(@default_system_prompt)
    field :context_messages, :integer, default: 20
    field :max_tokens, :integer, default: 512
    field :temperature, :float, default: 0.7
    field :rooms, {:array, :string}, default: []

    timestamps(type: :utc_datetime)
  end

  @fields [:name, :system_prompt, :context_messages, :max_tokens, :temperature, :rooms]

  def changeset(persona, attrs) do
    persona
    |> cast(attrs, @fields)
    |> update_change(:name, &String.trim/1)
    |> update_change(:rooms, &normalize_rooms/1)
    |> validate_required(@fields -- [:rooms])
    |> validate_length(:name, min: 2, max: 20)
    |> validate_format(:name, ~r/\A[a-zA-Z0-9_]+\z/,
      message: "may only contain letters, digits and underscores"
    )
    |> unsafe_validate_unique(:name, HoloChat.Repo)
    |> unique_constraint(:name)
    |> validate_length(:system_prompt, max: 4000)
    |> validate_number(:context_messages, greater_than_or_equal_to: 1, less_than_or_equal_to: 50)
    |> validate_number(:max_tokens, greater_than_or_equal_to: 16, less_than_or_equal_to: 4096)
    |> validate_number(:temperature, greater_than_or_equal_to: 0, less_than_or_equal_to: 2)
    |> validate_change(:rooms, &validate_rooms/2)
  end

  defp normalize_rooms(rooms) do
    rooms
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp validate_rooms(field, rooms) do
    case Enum.reject(rooms, &Chat.valid_room?/1) do
      [] -> []
      [invalid | _] -> [{field, "contains an invalid room name: #{invalid}"}]
    end
  end
end
