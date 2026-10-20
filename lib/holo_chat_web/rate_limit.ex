defmodule HoloChatWeb.RateLimit do
  @moduledoc """
  Rate limits for the authentication endpoints.

  Every attempt counts, successful or not. An action is denied as soon as
  any of the given identities (client IP, username) is over its limit, so
  password guessing is slowed down both per attacker and per targeted account.

  Behind a reverse proxy the client IP comes from its forwarding header, if the
  proxy is listed in `TRUSTED_PROXIES` (see `HoloChatWeb.ClientIP`).
  """

  use Hammer, backend: :ets, algorithm: :fix_window_per_key

  @minute :timer.minutes(1)
  @hour :timer.hours(1)

  # {max attempts, window in ms} per action and identity.
  @limits %{
    login: [ip: {20, 5 * @minute}, username: {10, 15 * @minute}],
    register: [ip: {5, @hour}],
    recover: [ip: {10, 15 * @minute}, username: {5, 15 * @minute}]
  }

  @doc """
  Records an attempt at `action` and returns `:ok` or `{:error, :rate_limited}`.

  `identities` is a keyword list such as `[ip: {127, 0, 0, 1}, username: "ada"]`.
  Identities without a configured limit for the action are ignored.
  """
  def check(action, identities) when is_map_key(@limits, action) do
    limits = Map.fetch!(@limits, action)

    results =
      for {kind, value} <- identities, {:ok, {limit, window}} <- [Keyword.fetch(limits, kind)] do
        hit("#{action}:#{kind}:#{normalize(kind, value)}", window, limit)
      end

    if Enum.any?(results, &match?({:deny, _}, &1)), do: {:error, :rate_limited}, else: :ok
  end

  defp normalize(:ip, ip) when is_tuple(ip), do: ip |> :inet.ntoa() |> to_string()
  # Unknown clients share one bucket rather than going unlimited.
  defp normalize(:ip, nil), do: "unknown"
  defp normalize(:username, username), do: username |> String.trim() |> String.downcase()
end
