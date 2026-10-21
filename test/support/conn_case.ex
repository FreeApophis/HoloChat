defmodule HoloChatWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use HoloChatWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]
  use ExUnit.CaseTemplate

  alias HoloChat.Accounts.Scope

  using do
    quote do
      # The default endpoint for testing
      @endpoint HoloChatWeb.Endpoint

      use HoloChatWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import HoloChatWeb.ConnCase
    end
  end

  setup tags do
    HoloChat.DataCase.setup_sandbox(tags)
    {:ok, conn: build_conn_with_unique_ip()}
  end

  @doc """
  Waits until the LiveView has handled the messages already sent to it.

  A test that received a PubSub broadcast may get there before the LiveView
  it shares the topic with: call this before asserting on the page.
  """
  def await_view(%Phoenix.LiveViewTest.View{pid: pid}) do
    _ = :sys.get_state(pid)
    :ok
  end

  @doc """
  Builds a conn whose client IP (as seen by controllers and LiveViews)
  is unique to it, so per-IP rate limits don't leak between async tests.
  """
  def build_conn_with_unique_ip do
    ip = unique_ip()

    Phoenix.ConnTest.build_conn()
    |> Map.put(:remote_ip, ip)
    |> Plug.Test.put_peer_data(%{address: ip, port: 4000, ssl_cert: nil})
  end

  @doc "Returns an IPv4 address no other call returns during this run."
  def unique_ip do
    <<a, b, c>> = <<System.unique_integer([:positive])::24>>
    {10, a, b, c}
  end

  @doc """
  Setup helper that registers and logs in users.

      setup :register_and_log_in_user

  It stores an updated connection and a registered user in the
  test context.
  """
  def register_and_log_in_user(%{conn: conn} = context) do
    user = HoloChat.AccountsFixtures.user_fixture()
    scope = Scope.for_user(user)

    opts =
      context
      |> Map.take([:token_authenticated_at])
      |> Enum.into([])

    %{conn: log_in_user(conn, user, opts), user: user, scope: scope}
  end

  @doc """
  Logs the given `user` into the `conn`.

  It returns an updated `conn`.
  """
  def log_in_user(conn, user, opts \\ []) do
    token = HoloChat.Accounts.generate_user_session_token(user)

    maybe_set_token_authenticated_at(token, opts[:token_authenticated_at])

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end

  defp maybe_set_token_authenticated_at(_token, nil), do: nil

  defp maybe_set_token_authenticated_at(token, authenticated_at) do
    HoloChat.AccountsFixtures.override_token_authenticated_at(token, authenticated_at)
  end
end
