defmodule HoloChatWeb.UserSessionControllerTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  alias HoloChat.Accounts

  setup do
    %{user: user_fixture()}
  end

  describe "POST /users/log-in - username and password" do
    test "logs the user in and shows them in the header", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"username" => user.username, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#current-username", user.username)
      assert has_element?(view, "#settings-link")
      assert has_element?(view, "#logout-link")
      refute has_element?(view, "#login-link")
      refute has_element?(view, "#admin-link")
    end

    test "shows admins the admin link", %{conn: conn, user: user} do
      {:ok, _} = Accounts.set_admin(user.username, true)

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"username" => user.username, "password" => valid_user_password()}
        })

      {:ok, view, _html} = live(conn, ~p"/")
      assert has_element?(view, "#admin-link[href='/admin/assistant']")
    end

    test "ignores the case of the username", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "username" => String.upcase(user.username),
            "password" => valid_user_password()
          }
        })

      assert get_session(conn, :user_token)
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{
            "username" => user.username,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_holo_chat_web_user_remember_me"]
      assert redirected_to(conn) == ~p"/"
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(~p"/users/log-in", %{
          "user" => %{"username" => user.username, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/foo/bar"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Welcome back!"
    end

    test "redirects to login page with invalid credentials", %{conn: conn, user: user} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"username" => user.username, "password" => "invalid_password"}
        })

      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid username or password"
      assert Phoenix.Flash.get(conn.assigns.flash, :username) == user.username
      assert redirected_to(conn) == ~p"/users/log-in"
    end

    test "blocks an account after too many attempts", %{conn: conn, user: user} do
      for _ <- 1..10 do
        post(build_conn_with_unique_ip(), ~p"/users/log-in", %{
          "user" => %{"username" => user.username, "password" => "wrong password!"}
        })
      end

      # Even the right password is refused while the limit is active.
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"username" => user.username, "password" => valid_user_password()}
        })

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Too many attempts"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "POST /users/log-in - one-time login token" do
    test "logs the user in", %{conn: conn, user: user} do
      token = Accounts.generate_login_token(user)

      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => token}})

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end

    test "rejects invalid tokens", %{conn: conn} do
      conn = post(conn, ~p"/users/log-in", %{"user" => %{"token" => "invalid"}})

      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or it has expired"
      assert redirected_to(conn) == ~p"/users/log-in"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn = conn |> log_in_user(user) |> delete(~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = delete(conn, ~p"/users/log-out")
      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :user_token)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Logged out successfully"
    end
  end
end
