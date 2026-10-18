defmodule HoloChatWeb.UserLive.Settings do
  use HoloChatWeb, :live_view

  on_mount {HoloChatWeb.UserAuth, :require_sudo_mode}

  import HoloChatWeb.UserLive.AccountComponents

  alias HoloChat.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-md space-y-10 py-8">
        <div class="text-center">
          <.header>
            Account settings
            <:subtitle>Signed in as {@current_scope.user.username}</:subtitle>
          </.header>
        </div>

        <section>
          <h2 class="mb-2 text-sm font-semibold">Change password</h2>
          <.form
            for={@password_form}
            id="password_form"
            action={~p"/users/update-password"}
            method="post"
            phx-change="validate_password"
            phx-submit="update_password"
            phx-trigger-action={@trigger_submit}
          >
            <input
              name={@password_form[:username].name}
              type="hidden"
              id="hidden_user_username"
              value={@current_scope.user.username}
            />
            <.input
              field={@password_form[:password]}
              type="password"
              label="New password"
              autocomplete="new-password"
              required
            />
            <.input
              field={@password_form[:password_confirmation]}
              type="password"
              label="Confirm new password"
              autocomplete="new-password"
            />
            <.button variant="primary" phx-disable-with="Saving...">Save password</.button>
          </.form>
        </section>

        <section id="recovery-codes-section">
          <h2 class="mb-2 text-sm font-semibold">Recovery codes</h2>
          <%= if @new_recovery_codes do %>
            <p class="text-sm opacity-80">
              Your new codes are below. Save them now; they won't be shown again.
              Your old codes no longer work.
            </p>
            <.recovery_code_list id="new-recovery-codes" codes={@new_recovery_codes} />
          <% else %>
            <p class="text-sm opacity-80">
              You have
              <span id="recovery-codes-count" class="font-semibold">{@recovery_codes_count}</span>
              unused recovery codes. Generating new ones replaces all of them.
            </p>
            <.button
              id="regenerate-codes"
              class="btn btn-soft mt-3"
              phx-click="regenerate_codes"
              phx-disable-with="Generating..."
            >
              Generate new recovery codes
            </.button>
          <% end %>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user
    password_changeset = Accounts.change_user_password(user, %{}, hash_password: false)

    socket =
      socket
      |> assign(:password_form, to_form(password_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:recovery_codes_count, Accounts.count_recovery_codes(user))
      |> assign(:new_recovery_codes, nil)

    {:ok, socket}
  end

  @impl true
  def handle_event("validate_password", params, socket) do
    %{"user" => user_params} = params

    password_form =
      socket.assigns.current_scope.user
      |> Accounts.change_user_password(user_params, hash_password: false)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, password_form: password_form)}
  end

  def handle_event("update_password", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)

    case Accounts.change_user_password(user, user_params) do
      %{valid?: true} = changeset ->
        {:noreply, assign(socket, trigger_submit: true, password_form: to_form(changeset))}

      changeset ->
        {:noreply, assign(socket, password_form: to_form(changeset, action: :insert))}
    end
  end

  def handle_event("regenerate_codes", _params, socket) do
    user = socket.assigns.current_scope.user
    true = Accounts.sudo_mode?(user)
    {:ok, codes} = Accounts.regenerate_recovery_codes(user)

    {:noreply, assign(socket, :new_recovery_codes, codes)}
  end
end
