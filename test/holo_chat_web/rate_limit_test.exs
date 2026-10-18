defmodule HoloChatWeb.RateLimitTest do
  use ExUnit.Case, async: true

  import HoloChatWeb.ConnCase, only: [unique_ip: 0]

  alias HoloChatWeb.RateLimit

  test "allows an action up to its limit, then denies it" do
    ip = unique_ip()

    for _ <- 1..5, do: assert(:ok = RateLimit.check(:register, ip: ip))
    assert {:error, :rate_limited} = RateLimit.check(:register, ip: ip)
  end

  test "counts each identity separately" do
    ip = unique_ip()
    for _ <- 1..5, do: RateLimit.check(:register, ip: ip)

    assert :ok = RateLimit.check(:register, ip: unique_ip())
  end

  test "denies when any identity is over its limit" do
    username = "victim#{System.unique_integer([:positive])}"

    # Ten attempts on one account from ten different IPs...
    for _ <- 1..10, do: assert(:ok = RateLimit.check(:login, ip: unique_ip(), username: username))

    # ...block the eleventh, whatever IP it comes from.
    assert {:error, :rate_limited} =
             RateLimit.check(:login, ip: unique_ip(), username: username)

    # Usernames are compared case-insensitively.
    assert {:error, :rate_limited} =
             RateLimit.check(:login, ip: unique_ip(), username: String.upcase(username))
  end
end
