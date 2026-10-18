defmodule HoloChat.ChatFixtures do
  @moduledoc """
  Test helpers for creating entities via the `HoloChat.Chat` context.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias HoloChat.Chat

  @doc "A room name no other test uses (PubSub is shared across async tests)."
  def unique_room, do: "room-#{System.unique_integer([:positive])}"

  def message_fixture(scope, room, attrs \\ %{}) do
    {:ok, message} = Chat.create_message(scope, room, Enum.into(attrs, %{"body" => "hello"}))
    message
  end
end
