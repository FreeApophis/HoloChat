defmodule HoloChatWeb.UserLive.RecoveryTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  alias HoloChat.Accounts

  setup do
    {user, codes} = user_with_recovery_codes_fixture()
    %{user: user, codes: codes}
  end

  test "renders the recovery form", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/users/recover")

    assert has_element?(lv, "#recovery_form input[name='recovery[username]']")
    assert has_element?(lv, "#recovery_form input[name='recovery[code]']")
    assert has_element?(lv, "#recovery_form input[name='recovery[password]']")
    assert has_element?(lv, "#recovery_form input[name='recovery[password_confirmation]']")
  end

  test "sets a new password and logs the user in", %{conn: conn, user: user, codes: [code | _]} do
    {:ok, lv, _html} = live(conn, ~p"/users/recover")

    form =
      form(lv, "#recovery_form",
        recovery: %{
          username: user.username,
          code: code,
          password: "brand new password",
          password_confirmation: "brand new password"
        }
      )

    render_submit(form)
    # Login happens via a separate form that carries only a one-time token.
    conn = follow_trigger_action(form(lv, "#recovery-login-form"), conn)

    assert redirected_to(conn) == ~p"/"
    assert get_session(conn, :user_token)
    assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "9 recovery codes left"
    assert Accounts.get_user_by_username_and_password(user.username, "brand new password")
  end

  test "rejects a wrong code without revealing whether the user exists",
       %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/users/recover")

    for username <- [user.username, "nobody"] do
      result =
        lv
        |> form("#recovery_form",
          recovery: %{
            username: username,
            code: "AAAA-AAAA-AAAA-AAAA",
            password: "brand new password",
            password_confirmation: "brand new password"
          }
        )
        |> render_submit()

      assert result =~ "Invalid username or recovery code"
    end

    assert Accounts.get_user_by_username_and_password(user.username, valid_user_password())
  end

  test "shows password errors and keeps the code", %{conn: conn, user: user, codes: [code | _]} do
    {:ok, lv, _html} = live(conn, ~p"/users/recover")

    result =
      lv
      |> form("#recovery_form",
        recovery: %{username: user.username, code: code, password: "short"}
      )
      |> render_submit()

    assert result =~ "should be at least 12 character"
    assert Accounts.count_recovery_codes(user) == 10
  end

  test "limits attempts per account", %{conn: conn, user: user, codes: [code | _]} do
    for _ <- 1..5 do
      {:ok, lv, _html} = live(build_conn_with_unique_ip(), ~p"/users/recover")

      lv
      |> form("#recovery_form",
        recovery: %{
          username: user.username,
          code: "AAAA-AAAA-AAAA-AAAA",
          password: "brand new password"
        }
      )
      |> render_submit()
    end

    {:ok, lv, _html} = live(conn, ~p"/users/recover")

    result =
      lv
      |> form("#recovery_form",
        recovery: %{username: user.username, code: code, password: "brand new password"}
      )
      |> render_submit()

    assert result =~ "Too many attempts"
    assert Accounts.count_recovery_codes(user) == 10
  end
end
