defmodule HoloChat.Rooms.Room do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias HoloChat.Characters.Tags

  schema "rooms" do
    field :name, :string
    field :kind, :string, default: "roleplay"
    field :title, :string
    field :topic, :string
    field :scenario, :string
    field :tags, {:array, :string}, default: []
    field :tag_list, :string, virtual: true
    field :reply_policy, :string, default: "natural"
    field :reply_delay, :integer, default: 4
    field :max_ai_turns, :integer, default: 2
    field :card_image_id, :binary_id
    field :background_image_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a new room: the name is chosen once and never changes.
  """
  def create_changeset(room, attrs) do
    room
    |> cast(attrs, [:name])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name])
    |> unique_constraint(:name, message: "is already taken")
    |> changeset(attrs)
  end

  @doc """
  Changeset for the scene a game master edits.
  """
  def changeset(room, attrs) do
    room
    |> cast(attrs, [:title, :topic, :scenario, :reply_policy, :reply_delay, :max_ai_turns])
    |> Tags.cast_tag_list(attrs)
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 60)
    |> validate_length(:topic, max: 160)
    |> validate_length(:scenario, max: 4000)
    |> validate_inclusion(:reply_policy, ~w(natural mention))
    |> validate_number(:reply_delay, greater_than_or_equal_to: 0, less_than_or_equal_to: 60)
    |> validate_number(:max_ai_turns, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
  end
end
