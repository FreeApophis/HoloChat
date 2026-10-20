defmodule HoloChat.Rooms.Topic do
  @moduledoc false

  use Ecto.Schema

  # A room's topic, by room name: rooms need no record to have one.
  @primary_key {:room, :string, autogenerate: false}
  schema "room_topics" do
    field :topic, :string

    timestamps(type: :utc_datetime)
  end
end
