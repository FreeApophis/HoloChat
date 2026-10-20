import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/holo_chat start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :holo_chat, HoloChatWeb.Endpoint, server: true
end

config :holo_chat, HoloChatWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :holo_chat, HoloChatWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/holo_chat_web/router\.ex$"E,
        ~r"lib/holo_chat_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  # The database is either one DATABASE_URL or its parts (DATABASE_HOST, ...).
  # The parts need no URL-encoding, so they suit passwords with special characters.
  database =
    case System.get_env("DATABASE_URL") do
      url when url not in [nil, ""] ->
        [url: url]

      _ ->
        [
          hostname: System.get_env("DATABASE_HOST", "localhost"),
          port: String.to_integer(System.get_env("DATABASE_PORT", "5432")),
          database: System.get_env("DATABASE_NAME", "holo_chat_prod"),
          username:
            System.get_env("DATABASE_USER") ||
              raise("""
              environment variable DATABASE_URL (or DATABASE_USER and DATABASE_PASSWORD) is missing.
              For example: ecto://USER:PASS@HOST/DATABASE
              """),
          password: System.get_env("DATABASE_PASSWORD", "")
        ]
    end

  # DATABASE_SSL=true verifies the server certificate against the system CAs, or
  # against DATABASE_SSL_CA_CERT (a PEM file) for a private CA.
  database_ssl =
    cond do
      System.get_env("DATABASE_SSL") not in ~w(true 1) -> false
      ca_cert = System.get_env("DATABASE_SSL_CA_CERT") -> [cacertfile: ca_cert]
      true -> true
    end

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :holo_chat,
         HoloChat.Repo,
         database ++
           [
             ssl: database_ssl,
             pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
             socket_options: maybe_ipv6
           ]

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  # Reverse proxies (addresses or CIDR ranges, comma-separated) whose
  # X-Forwarded-For names the client. Without them, rate limits see the proxy.
  config :holo_chat, :trusted_proxies, System.get_env("TRUSTED_PROXIES")

  config :holo_chat, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # PHX_SCHEME=http serves plain HTTP (e.g. on an intranet): no redirect to
  # HTTPS, http:// links on PORT, and LiveView accepts connections from
  # whichever address the page was opened with. Otherwise HTTPS is forced
  # (HSTS included), except on localhost.
  {url, force_ssl, check_origin} =
    case System.get_env("PHX_SCHEME", "https") do
      "http" ->
        {[host: host, port: String.to_integer(System.get_env("PORT", "4000")), scheme: "http"],
         nil, :conn}

      "https" ->
        {[host: host, port: 443, scheme: "https"],
         [rewrite_on: [:x_forwarded_proto], exclude: [hosts: ["localhost", "127.0.0.1"]]], true}

      other ->
        raise "PHX_SCHEME must be http or https, got: #{inspect(other)}"
    end

  config :holo_chat, :force_ssl, force_ssl

  default_ip = if match?({:win32, _}, :os.type()), do: "0.0.0.0", else: "::"

  listen_ip =
    case :inet.parse_address(String.to_charlist(System.get_env("PHX_IP", default_ip))) do
      {:ok, ip} -> ip
      {:error, _} -> raise "PHX_IP is not an IP address: #{inspect(System.get_env("PHX_IP"))}"
    end

  config :holo_chat, HoloChatWeb.Endpoint,
    url: url,
    check_origin: check_origin,
    http: [
      # PHX_IP is the address to listen on, e.g. 127.0.0.1 for this machine only.
      # By default all interfaces: IPv6 "::", which also accepts IPv4 on Linux
      # but not on Windows, where IPv4 "0.0.0.0" is used instead.
      ip: listen_ip
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :holo_chat, HoloChatWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :holo_chat, HoloChatWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :holo_chat, HoloChat.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://swoosh.hexdocs.pm/Swoosh.html#module-installation for details.
end
