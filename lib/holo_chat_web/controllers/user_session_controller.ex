defmodule HoloChatWeb.UserSessionController do
  use HoloChatWeb, :controller

  alias HoloChat.Accounts
  alias HoloChatWeb.{RateLimit, UserAuth}

  def create(conn, %{"_action" => "registered"} = params) do
    create(conn, params, "Welcome to HoloChat!")
  end

  def create(conn, %{"_action" => "recovered"} = params) do
    create(conn, params, fn user ->
      "Password reset. You have #{Accounts.count_recovery_codes(user)} recovery codes left."
    end)
  end

  def create(conn, params) do
    create(conn, params, "Welcome back!")
  end

  # one-time login token, issued right after registration or recovery
  defp create(conn, %{"user" => %{"token" => token} = user_params}, info) do
    case Accounts.login_user_by_login_token(token) do
      {:ok, user} ->
        info = if is_function(info, 1), do: info.(user), else: info

        conn
        |> put_flash(:info, info)
        |> UserAuth.log_in_user(user, user_params)

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "The login link is invalid or it has expired.")
        |> redirect(to: ~p"/users/log-in")
    end
  end

  # username + password login
  defp create(conn, %{"user" => user_params}, info) do
    %{"username" => username, "password" => password} = user_params

    with :ok <- RateLimit.check(:login, ip: conn.remote_ip, username: username),
         %Accounts.User{} = user <- Accounts.get_user_by_username_and_password(username, password) do
      conn
      |> put_flash(:info, info)
      |> UserAuth.log_in_user(user, user_params)
    else
      {:error, :rate_limited} ->
        login_failed(conn, username, "Too many attempts. Please wait a few minutes.")

      # In order to prevent user enumeration attacks, don't disclose whether the username exists.
      nil ->
        login_failed(conn, username, "Invalid username or password")
    end
  end

  def update_password(conn, %{"user" => user_params} = params) do
    user = conn.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, {_user, expired_tokens}} = Accounts.update_user_password(user, user_params)

    # disconnect all existing LiveViews with old sessions
    UserAuth.disconnect_sessions(expired_tokens)

    conn
    |> put_session(:user_return_to, ~p"/users/settings")
    |> create(params, "Password updated successfully!")
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end

  defp login_failed(conn, username, message) do
    conn
    |> put_flash(:error, message)
    |> put_flash(:username, String.slice(username, 0, 20))
    |> redirect(to: ~p"/users/log-in")
  end
end
