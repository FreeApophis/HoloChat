defmodule HoloChatWeb.HomeLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "as a guest" do
    test "the main page is a landing page, not the lobby", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#landing-hero")
      assert has_element?(view, "#landing-destinations #destination-risa")
      refute has_element?(view, "#room-list")
      refute has_element?(view, "#messages")
    end

    test "invites guests to sign up or look around the lobby", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#landing-signup[href='/users/register']")
      assert has_element?(view, "#landing-enter[href='/rooms/lobby']")
    end

    test "the lobby link opens the lobby", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      {:ok, lobby, _html} =
        view
        |> element("#landing-enter")
        |> render_click()
        |> follow_redirect(conn, ~p"/rooms/lobby")

      assert has_element?(lobby, "#room-title", "lobby")
    end
  end

  describe "as a user" do
    setup :register_and_log_in_user

    test "offers the lobby and scenes instead of sign-up", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert has_element?(view, "#landing-enter[href='/rooms/lobby']")
      assert has_element?(view, "#landing-roleplay[href='/scenarios']")
      refute has_element?(view, "#landing-signup")
    end
  end

  test "the header links to the lobby from every page", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/characters")

    assert has_element?(view, "#lobby-nav-link[href='/rooms/lobby']")
  end
end
