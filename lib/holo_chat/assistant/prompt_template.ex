defmodule HoloChat.Assistant.PromptTemplate do
  @moduledoc """
  An admin-written system prompt for cast characters in scenes, chosen per
  room. See `HoloChat.Assistant.ScenePrompt` for the placeholders.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "assistant_prompt_templates" do
    field :name, :string
    field :body, :string
    # Offered in rooms that speak it; see HoloChat.Rooms.languages/0.
    field :language, :string, default: "en"

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(template, attrs) do
    template
    |> cast(attrs, [:name, :body, :language])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :body])
    |> validate_length(:name, max: 80)
    |> validate_length(:body, max: 8000)
    |> validate_inclusion(:language, Enum.map(HoloChat.Rooms.languages(), &elem(&1, 0)))
    |> unique_constraint(:name)
  end
end
