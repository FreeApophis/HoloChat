defmodule HoloChatWeb.AdminLive.AssistantTest do
  use HoloChatWeb.ConnCase, async: true

  import Mox
  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures

  alias HoloChat.Accounts
  alias HoloChat.Assistant
  alias HoloChat.Assistant.LLMMock

  setup :verify_on_exit!

  describe "access" do
    test "guests are sent to log in", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in"}}} = live(conn, ~p"/admin/assistant")
    end

    test "non-admins are sent home", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, ~p"/admin/assistant")
    end
  end

  describe "as an admin" do
    setup %{conn: conn} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      %{conn: log_in_user(conn, admin)}
    end

    test "shows the current settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant")

      assert has_element?(
               view,
               "#assistant-settings-form input[name='settings[endpoint_url]'][value='http://localhost:5001']"
             )

      assert has_element?(
               view,
               "#assistant-settings-form input[name='settings[name]'][value='Holo']"
             )

      assert has_element?(
               view,
               "#assistant-settings-form textarea[name='settings[system_prompt]']"
             )
    end

    test "saves valid settings", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant")

      html =
        view
        |> form("#assistant-settings-form",
          settings: %{enabled: "true", name: "Kobold", endpoint_url: "http://gpu-box:5001"}
        )
        |> render_submit()

      assert html =~ "Settings saved"

      assert %{enabled: true, name: "Kobold", endpoint_url: "http://gpu-box:5001"} =
               Assistant.get_settings()
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/assistant")

      html =
        view
        |> form("#assistant-settings-form", settings: %{endpoint_url: "not a url"})
        |> render_submit()

      assert html =~ "must be an http:// or https:// URL"
      assert Assistant.get_settings().endpoint_url == "http://localhost:5001"
    end

    test "tests the connection to the endpoint being edited", %{conn: conn} do
      expect(LLMMock, :server_info, fn "http://gpu-box:5001" ->
        {:ok,
         %{
           models: ["gemma-31b"],
           server: "KoboldCpp 1.118.1",
           context_length: 65_536,
           generation_speed: 21.37
         }}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/assistant")

      view
      |> form("#assistant-settings-form", settings: %{endpoint_url: "http://gpu-box:5001"})
      |> render_change()

      view |> element("#test-connection") |> render_click()

      assert has_element?(view, "#connection-status", "gemma-31b")
      assert has_element?(view, "#connection-server", "KoboldCpp 1.118.1")
      assert has_element?(view, "#connection-context", "65,536 tokens")
      assert has_element?(view, "#connection-speed", "21.4 tokens/s")
    end

    test "only shows the details the server offers", %{conn: conn} do
      expect(LLMMock, :server_info, fn _ ->
        {:ok, %{models: ["llama"], server: nil, context_length: nil, generation_speed: nil}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/assistant")
      view |> element("#test-connection") |> render_click()

      assert has_element?(view, "#connection-status", "llama")
      refute has_element?(view, "#connection-server")
      refute has_element?(view, "#connection-context")
      refute has_element?(view, "#connection-speed")
    end

    test "warns when the context could outgrow the model's context window", %{conn: conn} do
      expect(LLMMock, :server_info, fn _ ->
        {:ok, %{models: ["tiny"], server: nil, context_length: 2048, generation_speed: nil}}
      end)

      {:ok, view, _html} = live(conn, ~p"/admin/assistant")
      view |> element("#test-connection") |> render_click()

      assert has_element?(view, "#context-warning")
    end

    test "reports a failed connection", %{conn: conn} do
      expect(LLMMock, :server_info, fn _ -> {:error, :econnrefused} end)
      {:ok, view, _html} = live(conn, ~p"/admin/assistant")

      view |> element("#test-connection") |> render_click()

      assert has_element?(view, "#connection-status", "Could not connect")
    end
  end
end
