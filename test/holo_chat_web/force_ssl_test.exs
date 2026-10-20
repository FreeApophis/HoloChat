defmodule HoloChatWeb.ForceSSLTest do
  # Changes the application environment, which is global.
  use HoloChatWeb.ConnCase, async: false

  setup do
    previous = Application.fetch_env(:holo_chat, :force_ssl)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:holo_chat, :force_ssl, value)
        :error -> Application.delete_env(:holo_chat, :force_ssl)
      end
    end)
  end

  test "redirects plain HTTP to HTTPS when configured", %{conn: conn} do
    Application.put_env(:holo_chat, :force_ssl, rewrite_on: [:x_forwarded_proto])

    conn = get(%{conn | host: "chat.example.com"}, ~p"/rooms/lobby")

    assert redirected_to(conn, 301) == "https://chat.example.com/rooms/lobby"
  end

  test "serves plain HTTP when not configured (PHX_SCHEME=http)", %{conn: conn} do
    Application.put_env(:holo_chat, :force_ssl, nil)

    conn = get(%{conn | host: "192.168.1.100"}, ~p"/rooms/lobby")

    assert html_response(conn, 200)
  end
end
