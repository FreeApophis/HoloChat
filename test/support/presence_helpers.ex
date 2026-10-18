defmodule HoloChatWeb.PresenceHelpers do
  @moduledoc """
  Deterministic waiting for Phoenix Presence updates in tests.

  The test process must be subscribed to the presence topic it waits on.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  import ExUnit.Assertions

  alias HoloChatWeb.Presence
  alias Phoenix.Socket.Broadcast
  alias Phoenix.Tracker.Shard

  @doc """
  Waits for a presence_diff that carries `expected` metadata. Once the
  tracker shard has finished broadcasting it, every subscribed LiveView
  has the diff in its mailbox, so the next render reflects it.
  """
  def await_presence(expected) do
    receive do
      %Broadcast{event: "presence_diff", payload: %{joins: joins}} ->
        if Enum.any?(joins, fn {_key, %{metas: metas}} ->
             Enum.any?(metas, &matches?(&1, expected))
           end) do
          :sys.get_state(Shard.name_for_number(Presence, 0))
          :ok
        else
          await_presence(expected)
        end
    after
      1000 -> flunk("no presence_diff with #{inspect(expected)}")
    end
  end

  @doc """
  Waits until all async presence fetchers have finished. Use in `on_exit`.
  """
  def await_presence_fetchers do
    for pid <- Presence.fetchers_pids() do
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, _, _, _}, 1000
    end
  end

  defp matches?(meta, expected), do: Map.take(meta, Map.keys(expected)) == expected
end
