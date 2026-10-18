defmodule HoloChat.CharactersFixtures do
  @moduledoc """
  Test helpers for creating entities via the `HoloChat.Characters` context.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias HoloChat.Characters

  @doc "A tag no other test uses (the library is shared across async tests)."
  def unique_tag, do: "tag-#{System.unique_integer([:positive])}"

  def character_fixture(scope, attrs \\ %{}) do
    {:ok, character} =
      Characters.create_character(scope, Enum.into(attrs, %{"name" => "Someone"}))

    character
  end
end
