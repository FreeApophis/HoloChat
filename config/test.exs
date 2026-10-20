import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :pbkdf2_elixir, :rounds, 1

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :holo_chat, HoloChat.Repo,
  username: "holo_chat",
  password: "holo_chat",
  hostname: "localhost",
  database: "holo_chat_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :holo_chat, HoloChatWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Tc9hzUvw+l5BgueDdWTqrUxqWr7swXVwrXEqAdEmsUNNXwk5Xy7aKs4wBkZTJmRw",
  server: false

# Reverse proxies that may name the client in X-Forwarded-For (TEST-NET-1;
# ConnCase clients use 10.0.0.0/8).
config :holo_chat, :trusted_proxies, "192.0.2.0/24"

# In test we don't send emails
config :holo_chat, HoloChat.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# The assistant talks to a Mox mock in tests, and the lobby assistant
# server is started per test (see HoloChat.Assistant.Server) instead.
config :holo_chat, :assistant_llm, HoloChat.Assistant.LLMMock
config :holo_chat, :start_assistant, false

config :holo_chat, HoloChat.Assistant.OpenAICompatibleClient,
  req_options: [plug: {Req.Test, HoloChat.Assistant.OpenAICompatibleClient}, retry: false]
