defmodule HoloChat.Characters.Character do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias HoloChat.Characters.Tags

  schema "characters" do
    field :name, :string
    field :owner_id, :id
    field :avatar_id, :binary_id
    field :tags, {:array, :string}, default: []
    field :tag_list, :string, virtual: true
    field :description, :string
    field :personality, :string
    field :example_dialogue, :string

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for the character sheet. The owner and avatar are set by the
  server, never cast.
  """
  def changeset(character, attrs) do
    character
    |> cast(attrs, [:name, :description, :personality, :example_dialogue])
    |> Tags.cast_tag_list(attrs)
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> validate_length(:name, max: 60)
    |> validate_length(:description, max: 4000)
    |> validate_length(:personality, max: 2000)
    |> validate_length(:example_dialogue, max: 4000)
  end
end
