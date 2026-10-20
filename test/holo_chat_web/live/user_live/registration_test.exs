defmodule HoloChatWeb.UserLive.RegistrationTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  alias HoloChat.Accounts
  alias HoloChat.Accounts.User

  describe "registration page" do
    test "renders the registration form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      assert has_element?(lv, "#registration_form input[name='user[username]']")
      assert has_element?(lv, "#registration_form input[name='user[password]']")
      assert has_element?(lv, "#registration_form input[name='user[password_confirmation]']")
      assert has_element?(lv, "a[href='/users/log-in']")
    end

    test "redirects if already logged in", %{conn: conn} do
      result =
        conn
        |> log_in_user(user_fixture())
        |> live(~p"/users/register")
        |> follow_redirect(conn, ~p"/")

      assert {:ok, _conn} = result
    end

    test "renders errors while typing", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> element("#registration_form")
        |> render_change(user: %{"username" => "no spaces", "password" => "short"})

      assert result =~ "may only contain letters, digits and underscores"
      assert result =~ "should be at least 12 character"
    end

    test "renders an error for a taken username", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/register")

      result =
        lv
        |> form("#registration_form", user: valid_user_attributes(username: user.username))
        |> render_submit()

      assert result =~ "has already been taken"
    end
  end

  describe "successful registration" do
    setup %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/register")
      username = unique_username()

      lv
      |> form("#registration_form",
        user: %{
          username: username,
          password: valid_user_password(),
          password_confirmation: valid_user_password()
        }
      )
      |> render_submit()

      %{lv: lv, username: username}
    end

    test "creates the account and shows ten recovery codes once", %{lv: lv, username: username} do
      assert Accounts.get_user_by_username(username)
      refute has_element?(lv, "#registration_form")

      codes =
        lv
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#recovery-codes li")

      assert Enum.count(codes) == 10
    end

    test "logs the user in once they continue", %{conn: conn, lv: lv} do
      form = form(lv, "#continue-form")
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end
  end

  describe "rate limiting" do
    test "limits sign-ups per IP", %{conn: conn} do
      for _ <- 1..5 do
        {:ok, lv, _html} = live(conn, ~p"/users/register")

        lv
        |> form("#registration_form", user: valid_user_attributes())
        |> render_submit()
      end

      {:ok, lv, _html} = live(conn, ~p"/users/register")
      attrs = valid_user_attributes()

      result =
        lv
        |> form("#registration_form", user: attrs)
        |> render_submit()

      assert result =~ "Too many sign-ups"
      refute Accounts.get_user_by_username(attrs.username)
    end

    test "behind a trusted proxy, limits each forwarded client on its own" do
      # config/test.exs trusts the proxies in 192.0.2.0/24.
      proxy_conn = fn client_ip ->
        build_conn()
        |> Plug.Test.put_peer_data(%{address: {192, 0, 2, 1}, port: 4000, ssl_cert: nil})
        |> put_req_header("x-forwarded-for", "#{:inet.ntoa(client_ip)}, 192.0.2.7")
      end

      first_client = proxy_conn.(unique_ip())
      for _ <- 1..5, do: sign_up(first_client)

      assert {_html, %User{}} = sign_up(proxy_conn.(unique_ip()))
      assert {html, nil} = sign_up(first_client)
      assert html =~ "Too many sign-ups"
    end

    test "ignores forwarding headers from untrusted clients", %{conn: conn} do
      spoofing = fn -> put_req_header(conn, "x-forwarded-for", "#{:inet.ntoa(unique_ip())}") end

      for _ <- 1..5, do: sign_up(spoofing.())

      assert {html, nil} = sign_up(spoofing.())
      assert html =~ "Too many sign-ups"
    end
  end

  # Signs up a new user; returns the rendered result and the user, if created.
  defp sign_up(conn) do
    {:ok, lv, _html} = live(conn, ~p"/users/register")
    username = unique_username()
    password = valid_user_password()

    html =
      lv
      |> form("#registration_form",
        user: %{username: username, password: password, password_confirmation: password}
      )
      |> render_submit()

    {html, Accounts.get_user_by_username(username)}
  end
end
