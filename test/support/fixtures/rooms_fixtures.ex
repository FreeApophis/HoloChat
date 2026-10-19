defmodule HoloChat.RoomsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `HoloChat.Rooms` context.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  import HoloChat.ChatFixtures, only: [unique_room: 0]
  import HoloChat.ScenariosFixtures, only: [scenario_fixture: 2]

  alias HoloChat.Rooms

  @doc """
  Creates a role-play room. Without a `"scenario_id"`, it plays a new
  scenario made from the other attributes (title, topic, description, tags).
  """
  def roleplay_room_fixture(scope, attrs \\ %{}) do
    attrs = Map.new(attrs)
    {room_attrs, scenario_attrs} = Map.split(attrs, ["name", "scenario_id"])

    room_attrs =
      room_attrs
      |> Map.put_new("name", unique_room())
      |> Map.put_new_lazy("scenario_id", fn -> scenario_fixture(scope, scenario_attrs).id end)

    {:ok, room} = Rooms.create_roleplay_room(scope, room_attrs)
    room
  end
end
