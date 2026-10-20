defmodule HoloChatWeb.ClientIP do
  @moduledoc """
  The client's IP address behind trusted reverse proxies, for rate limiting.

  Proxies listed in the `:trusted_proxies` config (addresses or CIDR ranges,
  comma-separated, e.g. from `TRUSTED_PROXIES`) may name the client in
  `X-Forwarded-For`. The header is read from the right, skipping trusted hops;
  whatever comes before the first untrusted address could be forged by the
  client and is ignored. Without trusted proxies the header is never read.

  As a plug it rewrites `conn.remote_ip`. LiveViews use `from_connect_info/1`.
  """

  @behaviour Plug

  import Bitwise

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    header = conn |> Plug.Conn.get_req_header("x-forwarded-for") |> Enum.join(",")
    %{conn | remote_ip: resolve(conn.remote_ip, header, trusted_proxies())}
  end

  @doc """
  The client IP of a LiveView connection (`:peer_data` and `:x_headers`), or `nil`.
  """
  def from_connect_info(get_info) when is_function(get_info, 1) do
    case get_info.(:peer_data) do
      %{address: peer} ->
        header =
          for {"x-forwarded-for", value} <- get_info.(:x_headers) || [], into: "", do: value

        resolve(peer, header, trusted_proxies())

      _ ->
        nil
    end
  end

  @doc """
  Resolves the client IP from the peer address, the `X-Forwarded-For` value
  (or `nil`) and the parsed trusted proxies.
  """
  def resolve(peer, header, proxies) do
    peer = unmap(peer)

    if trusted?(peer, proxies) do
      header
      |> forwarded_hops()
      |> Enum.drop_while(&(&1 != :error and trusted?(&1, proxies)))
      |> case do
        [ip | _] when ip != :error -> ip
        _ -> peer
      end
    else
      peer
    end
  end

  @doc """
  Parses a comma-separated list of addresses and CIDR ranges. Raises on invalid entries.
  """
  def parse_proxies(nil), do: []

  def parse_proxies(list) when is_binary(list) do
    list
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_range/1)
  end

  defp parse_range(entry) do
    {address, bits} =
      case String.split(entry, "/", parts: 2) do
        [address] -> {address, nil}
        [address, bits] -> {address, Integer.parse(bits)}
      end

    with {:ok, ip} <- :inet.parse_strict_address(String.to_charlist(address)),
         size = if(tuple_size(ip) == 4, do: 32, else: 128),
         {prefix, ""} when prefix in 0..size//1 <- bits || {size, ""} do
      {to_integer(ip), size, prefix}
    else
      _ -> raise ArgumentError, "invalid trusted proxy #{inspect(entry)}"
    end
  end

  defp forwarded_hops(nil), do: []

  defp forwarded_hops(header) do
    header
    |> String.split(",", trim: true)
    |> Enum.reverse()
    |> Enum.map(fn hop ->
      case hop |> String.trim() |> String.to_charlist() |> :inet.parse_strict_address() do
        {:ok, ip} -> unmap(ip)
        {:error, _} -> :error
      end
    end)
  end

  defp trusted?(ip, proxies) do
    {value, size} = {to_integer(ip), if(tuple_size(ip) == 4, do: 32, else: 128)}

    Enum.any?(proxies, fn {range, range_size, prefix} ->
      range_size == size and value >>> (size - prefix) == range >>> (size - prefix)
    end)
  end

  # Dual-stack sockets report IPv4 clients as ::ffff:a.b.c.d.
  defp unmap({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: {high >>> 8, high &&& 0xFF, low >>> 8, low &&& 0xFF}

  defp unmap(ip), do: ip

  defp to_integer({_, _, _, _} = ip), do: ip |> Tuple.to_list() |> from_parts(8)
  defp to_integer(ip), do: ip |> Tuple.to_list() |> from_parts(16)

  defp from_parts(parts, bits), do: Enum.reduce(parts, 0, &(&2 <<< bits ||| &1))

  defp trusted_proxies do
    :holo_chat |> Application.get_env(:trusted_proxies) |> parse_proxies()
  end
end
