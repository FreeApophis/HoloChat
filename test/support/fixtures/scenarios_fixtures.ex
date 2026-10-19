defmodule HoloChat.ScenariosFixtures do
  @moduledoc """
  Test helpers for creating entities via the `HoloChat.Scenarios` context.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias HoloChat.Scenarios

  def scenario_fixture(scope, attrs \\ %{}) do
    {:ok, scenario} =
      Scenarios.create_scenario(scope, Enum.into(attrs, %{"title" => "A Scenario"}))

    scenario
  end
end
