defmodule HoloChatWeb.ClientIPTest do
  use ExUnit.Case, async: true

  alias HoloChatWeb.ClientIP

  @proxies ClientIP.parse_proxies("192.0.2.0/24, 2001:db8::1")

  describe "resolve/3" do
    test "takes the peer when it isn't a trusted proxy" do
      assert ClientIP.resolve({10, 0, 0, 1}, "203.0.113.9", @proxies) == {10, 0, 0, 1}
    end

    test "takes the forwarded client when the peer is a trusted proxy" do
      assert ClientIP.resolve({192, 0, 2, 1}, "203.0.113.9", @proxies) == {203, 0, 113, 9}
    end

    test "skips trusted hops and ignores what the client claims before them" do
      header = "198.51.100.1, 203.0.113.9, 192.0.2.7"
      assert ClientIP.resolve({192, 0, 2, 1}, header, @proxies) == {203, 0, 113, 9}
    end

    test "understands IPv6 proxies and clients" do
      ipv6_proxy = {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}

      assert ClientIP.resolve(ipv6_proxy, "2001:db8::42", @proxies) ==
               {0x2001, 0xDB8, 0, 0, 0, 0, 0, 0x42}
    end

    test "treats IPv4-mapped IPv6 peers (from dual-stack sockets) as IPv4" do
      mapped_proxy = {0, 0, 0, 0, 0, 0xFFFF, 0xC000, 0x0201}
      assert ClientIP.resolve(mapped_proxy, "203.0.113.9", @proxies) == {203, 0, 113, 9}
      assert ClientIP.resolve({0, 0, 0, 0, 0, 0xFFFF, 0x0A00, 0x0001}, nil, []) == {10, 0, 0, 1}
    end

    test "falls back to the peer without a usable header" do
      assert ClientIP.resolve({192, 0, 2, 1}, nil, @proxies) == {192, 0, 2, 1}
      assert ClientIP.resolve({192, 0, 2, 1}, "garbage", @proxies) == {192, 0, 2, 1}
    end

    test "trusts nothing without configured proxies" do
      assert ClientIP.resolve({192, 0, 2, 1}, "203.0.113.9", []) == {192, 0, 2, 1}
    end
  end

  describe "parse_proxies/1" do
    test "accepts addresses and CIDR ranges" do
      assert [_, _] = ClientIP.parse_proxies("10.0.0.0/8, ::1")
      assert ClientIP.parse_proxies("") == []
      assert ClientIP.parse_proxies(nil) == []
    end

    test "raises on invalid entries" do
      assert_raise ArgumentError, ~r/not-an-ip/, fn -> ClientIP.parse_proxies("not-an-ip") end

      assert_raise ArgumentError, ~r/10.0.0.0\/99/, fn ->
        ClientIP.parse_proxies("10.0.0.0/99")
      end
    end
  end
end
