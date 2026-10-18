defmodule HoloChatWeb.Router do
  use HoloChatWeb, :router

  import HoloChatWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HoloChatWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Other scopes may use custom stacks.
  # scope "/api", HoloChatWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:holo_chat, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: HoloChatWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", HoloChatWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{HoloChatWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  ## Admin routes (admins are granted with `mix holo_chat.admin`)

  scope "/admin", HoloChatWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_admin, on_mount: [{HoloChatWeb.UserAuth, :require_admin}] do
      live "/assistant", AdminLive.Assistant, :edit
    end
  end

  scope "/", HoloChatWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{HoloChatWeb.UserAuth, :mount_current_scope}] do
      # Guests can read the chat; posting requires a user.
      live "/", ChatLive
      live "/rooms/:room", ChatLive

      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/recover", UserLive.Recovery, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end
end
