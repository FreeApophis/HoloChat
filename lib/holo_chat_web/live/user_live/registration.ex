defmodule HoloChatWeb.UserLive.Registration do
  use HoloChatWeb, :live_view

  import HoloChatWeb.UserLive.AccountComponents

  alias HoloChat.Accounts
  alias HoloChat.Accounts.User
  alias HoloChatWeb.RateLimit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-sm py-8">
        <%= if @recovery_codes do %>
          <.header>
            Save your recovery codes
            <:subtitle>
              HoloChat has no email, so these codes are the only way back into your
              account if you forget your password. Each code works once.
              They won't be shown again.
            </:subtitle>
          </.header>

          <.recovery_code_list id="recovery-codes" codes={@recovery_codes} />

          <.form
            for={@login_form}
            id="continue-form"
            action={~p"/users/log-in?_action=registered"}
            phx-submit="continue"
            phx-trigger-action={@trigger_submit}
            class="mt-6"
          >
            <input type="hidden" name={@login_form[:token].name} value={@login_form[:token].value} />
            <.button variant="primary" class="w-full" phx-disable-with="Logging in...">
              I've saved my codes, continue <span aria-hidden="true">→</span>
            </.button>
          </.form>
        <% else %>
          <div class="text-center">
            <.header>
              Create an account
              <:subtitle>
                Already registered?
                <.link navigate={~p"/users/log-in"} class="font-semibold text-primary hover:underline">
                  Log in
                </.link>
                to your account now.
              </:subtitle>
            </.header>
          </div>

          <.form for={@form} id="registration_form" phx-submit="save" phx-change="validate">
            <.input
              field={@form[:username]}
              type="text"
              label="Username"
              autocomplete="username"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
            />
            <.input
              field={@form[:password]}
              type="password"
              label="Password"
              autocomplete="new-password"
              required
            />
            <.input
              field={@form[:password_confirmation]}
              type="password"
              label="Confirm password"
              autocomplete="new-password"
            />

            <.button phx-disable-with="Creating account..." class="btn btn-primary w-full">
              Create an account
            </.button>
          </.form>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, %{assigns: %{current_scope: %{user: user}}} = socket)
      when not is_nil(user) do
    {:ok, redirect(socket, to: HoloChatWeb.UserAuth.signed_in_path(socket))}
  end

  def mount(_params, _session, socket) do
    changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)

    {:ok,
     socket
     |> assign(:client_ip, client_ip(socket))
     |> assign(:recovery_codes, nil)
     |> assign(:trigger_submit, false)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("save", %{"user" => user_params}, socket) do
    with :ok <- RateLimit.check(:register, ip: socket.assigns.client_ip),
         {:ok, {user, codes}} <- Accounts.register_user(user_params) do
      token = Accounts.generate_login_token(user)

      {:noreply,
       socket
       |> assign(:recovery_codes, codes)
       |> assign(:login_form, to_form(%{"token" => token}, as: "user"))}
    else
      {:error, :rate_limited} ->
        {:noreply,
         put_flash(socket, :error, "Too many sign-ups from your network. Please try again later.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset = Accounts.change_user_registration(%User{}, user_params, validate_unique: false)
    {:noreply, assign_form(socket, Map.put(changeset, :action, :validate))}
  end

  def handle_event("continue", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, form: to_form(changeset, as: "user"))
  end
end
