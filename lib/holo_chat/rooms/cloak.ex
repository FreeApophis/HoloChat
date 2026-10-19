defmodule HoloChat.Rooms.Cloak do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # The library character a player wears in a room (by name: chat rooms have
  # no record).
  schema "cloaks" do
    field :user_id, :id
    field :room, :string
    field :character_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc """
  All fields are set by the server; this only maps the constraints.
  """
  def changeset(cloak) do
    cloak
    |> change()
    |> unique_constraint([:room, :character_id], name: :cloaks_room_character_id_index)
  end
end
