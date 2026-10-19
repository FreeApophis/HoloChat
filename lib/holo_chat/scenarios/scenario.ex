defmodule HoloChat.Scenarios.Scenario do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  alias HoloChat.Characters.Tags

  schema "scenarios" do
    field :title, :string
    field :topic, :string
    field :description, :string
    field :tags, {:array, :string}, default: []
    field :tag_list, :string, virtual: true
    field :owner_id, :id
    field :card_image_id, :binary_id
    field :background_image_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for the scenario's text. The owner and images are set by the
  server, never cast.
  """
  def changeset(scenario, attrs) do
    scenario
    |> cast(attrs, [:title, :topic, :description])
    |> Tags.cast_tag_list(attrs)
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title])
    |> validate_length(:title, max: 60)
    |> validate_length(:topic, max: 160)
    |> validate_length(:description, max: 4000)
  end
end
