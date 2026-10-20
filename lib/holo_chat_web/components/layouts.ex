defmodule HoloChatWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HoloChatWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://phoenix.hexdocs.pm/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex h-dvh flex-col">
      <header class="flex items-center justify-between border-b border-base-300 px-4 py-3 sm:px-6">
        <.link navigate={~p"/"} class="flex items-center gap-2 transition-opacity hover:opacity-80">
          <span class="grid size-8 place-items-center rounded-lg bg-primary text-primary-content">
            <.icon name="hero-chat-bubble-left-right" class="size-5" />
          </span>
          <span class="text-lg font-semibold tracking-tight">HoloChat</span>
        </.link>
        <nav class="flex items-center gap-2 text-sm sm:gap-3">
          <.link
            id="lobby-nav-link"
            navigate={~p"/rooms/lobby"}
            class="rounded-lg p-1.5 transition hover:bg-base-200"
            aria-label="Lobby"
            title="Lobby"
          >
            <.icon name="hero-chat-bubble-left-right" class="size-5" />
          </.link>
          <.link
            id="roleplay-nav-link"
            navigate={~p"/scenarios"}
            class="rounded-lg p-1.5 text-violet-600 transition hover:bg-base-200"
            aria-label="Scenarios and scenes"
            title="Scenarios and scenes"
          >
            <.icon name="hero-sparkles" class="size-5" />
          </.link>
          <.link
            id="news-nav-link"
            navigate={~p"/news"}
            class="rounded-lg p-1.5 transition hover:bg-base-200"
            aria-label="News"
            title="News"
          >
            <.icon name="hero-newspaper" class="size-5" />
          </.link>
          <.link
            id="characters-nav-link"
            navigate={~p"/characters"}
            class="rounded-lg p-1.5 transition hover:bg-base-200"
            aria-label="Characters"
            title="Characters"
          >
            <.icon name="hero-user-group" class="size-5" />
          </.link>
          <%= if @current_scope do %>
            <.link
              id="current-username"
              navigate={~p"/users/profile"}
              class="flex items-center gap-2 rounded-lg py-1 pr-2 pl-1 font-medium transition hover:bg-base-200"
              title="Your profile"
            >
              <.avatar
                name={@current_scope.user.username}
                avatar_id={@current_scope.user.avatar_id}
                class="size-7 text-xs"
              />
              <span class="hidden sm:inline">{@current_scope.user.username}</span>
            </.link>
            <.link
              :if={@current_scope.user.is_admin}
              id="admin-link"
              navigate={~p"/admin/assistant"}
              class="rounded-lg p-1.5 transition hover:bg-base-200"
              aria-label="Admin"
              title="Admin"
            >
              <.icon name="hero-wrench-screwdriver" class="size-5" />
            </.link>
            <.link
              id="settings-link"
              navigate={~p"/users/settings"}
              class="rounded-lg p-1.5 transition hover:bg-base-200"
              aria-label="Settings"
              title="Settings"
            >
              <.icon name="hero-cog-6-tooth" class="size-5" />
            </.link>
            <.link
              id="logout-link"
              href={~p"/users/log-out"}
              method="delete"
              class="rounded-lg p-1.5 transition hover:bg-base-200"
              aria-label="Log out"
              title="Log out"
            >
              <.icon name="hero-arrow-right-start-on-rectangle" class="size-5" />
            </.link>
          <% else %>
            <.link
              id="login-link"
              navigate={~p"/users/log-in"}
              class="rounded-lg px-3 py-1.5 font-medium transition hover:bg-base-200"
            >
              Log in
            </.link>
            <.link
              id="register-link"
              navigate={~p"/users/register"}
              class="rounded-lg bg-primary px-3 py-1.5 font-medium text-primary-content transition hover:opacity-90"
            >
              Sign up
            </.link>
          <% end %>
          <.theme_toggle />
        </nav>
      </header>

      <main class="flex min-h-0 flex-1 flex-col px-4 py-4 sm:px-6">
        <div class="mx-auto flex min-h-0 w-full max-w-5xl flex-1 flex-col">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={
          show(".phx-client-error #client-error")
          |> JS.remove_attribute("hidden", to: ".phx-client-error #client-error")
        }
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={
          show(".phx-server-error #server-error")
          |> JS.remove_attribute("hidden", to: ".phx-server-error #server-error")
        }
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 [[data-theme-source=system]_&]:!left-0 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
