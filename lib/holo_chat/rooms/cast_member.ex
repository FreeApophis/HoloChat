defmodule HoloChat.Rooms.CastMember do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "room_cast" do
    field :room_id, :id, primary_key: true
    field :character_id, :id, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
