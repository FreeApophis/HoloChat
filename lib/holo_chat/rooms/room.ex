defmodule HoloChat.Rooms.Room do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "rooms" do
    field :name, :string
    field :kind, :string, default: "roleplay"
    field :title, :string
    field :topic, :string
    field :scenario, :string
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
    |> cast(attrs, [:title, :topic, :scenario])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 60)
    |> validate_length(:topic, max: 160)
    |> validate_length(:scenario, max: 4000)
  end
end
