defmodule HoloChatWeb.UserLive.LoginTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures

  describe "login page" do
    test "renders the username/password form with links", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      assert has_element?(lv, "#login_form input[name='user[username]']")
      assert has_element?(lv, "#login_form input[name='user[password]'][type='password']")
      assert has_element?(lv, "a[href='/users/register']")
      assert has_element?(lv, "a[href='/users/recover']")
      refute has_element?(lv, "input[type='email']")
    end
  end

  describe "user login" do
    test "logs in with valid credentials", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form =
        form(lv, "#login_form", user: %{username: user.username, password: valid_user_password()})

      render_submit(form, %{user: %{remember_me: "true"}})
      conn = follow_trigger_action(form, conn)

      assert redirected_to(conn) == ~p"/"
      assert get_session(conn, :user_token)
    end

    test "redirects back to login with an error for invalid credentials", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      form = form(lv, "#login_form", user: %{username: "nobody", password: "123456789012"})
      render_submit(form)
      conn = follow_trigger_action(form, conn)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid username or password"
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "keeps the username after a failed attempt", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"username" => "ada", "password" => "wrong password!"}
        })

      {:ok, lv, _html} = live(conn, ~p"/users/log-in")

      assert has_element?(lv, "#login_form input[name='user[username]'][value='ada']")
    end
  end

  describe "re-authentication (sudo mode)" do
    test "shows the logged-in username, read-only", %{conn: conn} do
      user = user_fixture()
      {:ok, lv, _html} = conn |> log_in_user(user) |> live(~p"/users/log-in")

      assert has_element?(
               lv,
               "#login_form input[name='user[username]'][value='#{user.username}'][readonly]"
             )
    end
  end
end
