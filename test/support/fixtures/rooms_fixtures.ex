defmodule HoloChat.RoomsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `HoloChat.Rooms` context.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  import HoloChat.ChatFixtures, only: [unique_room: 0]

  alias HoloChat.Rooms

  def roleplay_room_fixture(scope, attrs \\ %{}) do
    {:ok, room} =
      Rooms.create_roleplay_room(
        scope,
        Enum.into(attrs, %{"name" => unique_room(), "title" => "A Scene"})
      )

    room
  end
end
