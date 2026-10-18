defmodule HoloChat.Rooms.GameMaster do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "room_masters" do
    field :room_id, :id, primary_key: true
    field :user_id, :id, primary_key: true

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
