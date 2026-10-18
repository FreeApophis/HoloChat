defmodule HoloChatWeb.UserLive.Recovery do
  use HoloChatWeb, :live_view

  import HoloChatWeb.UserLive.AccountComponents

  alias HoloChat.Accounts
  alias HoloChatWeb.RateLimit

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-sm py-8">
        <div class="text-center">
          <.header>
            Reset your password
            <:subtitle>
              Use one of the recovery codes you saved when you signed up.
            </:subtitle>
          </.header>
        </div>

        <.form for={@form} id="recovery_form" phx-submit="recover">
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
            field={@form[:code]}
            type="text"
            label="Recovery code"
            placeholder="XXXX-XXXX-XXXX-XXXX"
            autocomplete="off"
            spellcheck="false"
            required
          />
          <.input
            field={@form[:password]}
            type="password"
            label="New password"
            autocomplete="new-password"
            required
          />
          <.input
            field={@form[:password_confirmation]}
            type="password"
            label="Confirm new password"
            autocomplete="new-password"
          />
          <.button phx-disable-with="Resetting..." class="btn btn-primary w-full">
            Reset password and log in
          </.button>
        </.form>

        <.form
          :if={@login_form}
          for={@login_form}
          id="recovery-login-form"
          action={~p"/users/log-in?_action=recovered"}
          phx-trigger-action={true}
        >
          <input type="hidden" name={@login_form[:token].name} value={@login_form[:token].value} />
        </.form>

        <p class="mt-4 text-center text-sm opacity-70">
          <.link navigate={~p"/users/log-in"} class="font-semibold text-primary hover:underline">
            Back to log in
          </.link>
        </p>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:client_ip, client_ip(socket))
     |> assign(:login_form, nil)
     |> assign(:form, to_form(%{}, as: :recovery))}
  end

  @impl true
  def handle_event("recover", %{"recovery" => params}, socket) do
    username = params["username"] || ""
    code = params["code"] || ""
    password_attrs = Map.take(params, ["password", "password_confirmation"])

    with :ok <- RateLimit.check(:recover, ip: socket.assigns.client_ip, username: username),
         {:ok, {user, _expired_tokens}} <- Accounts.recover_user(username, code, password_attrs) do
      token = Accounts.generate_login_token(user)
      {:noreply, assign(socket, :login_form, to_form(%{"token" => token}, as: :user))}
    else
      {:error, :rate_limited} ->
        {:noreply, error(socket, params, "Too many attempts. Please wait a few minutes.")}

      {:error, :invalid_recovery_code} ->
        {:noreply, error(socket, params, "Invalid username or recovery code.")}

      {:error, %Ecto.Changeset{errors: errors}} ->
        {:noreply, assign(socket, :form, to_form(params, as: :recovery, errors: errors))}
    end
  end

  defp error(socket, params, message) do
    socket
    |> put_flash(:error, message)
    |> assign(:form, to_form(Map.drop(params, ["code"]), as: :recovery))
  end
end
