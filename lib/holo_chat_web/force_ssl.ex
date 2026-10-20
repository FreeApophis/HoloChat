defmodule HoloChatWeb.ForceSSL do
  @moduledoc """
  Redirects plain HTTP to HTTPS with `Plug.SSL`, configured at runtime.

  Phoenix's own `:force_ssl` endpoint option is fixed when the release is
  built. This reads the `:force_ssl` config of `:holo_chat` (the `Plug.SSL`
  options, or `nil` to serve plain HTTP) instead, which `config/runtime.exs`
  sets from `PHX_SCHEME`.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case Application.get_env(:holo_chat, :force_ssl) do
      nil -> conn
      ssl_opts -> Plug.SSL.call(conn, Plug.SSL.init(ssl_opts))
    end
  end
end
