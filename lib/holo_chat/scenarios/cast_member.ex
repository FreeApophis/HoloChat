defmodule HoloChat.Scenarios.CastMember do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "scenario_cast" do
    field :scenario_id, :id, primary_key: true
    field :character_id, :id, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
