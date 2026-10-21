defmodule HoloChatWeb.UserLive.Profile do
  use HoloChatWeb, :live_view

  alias HoloChat.Accounts

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-md space-y-6 py-8">
        <.header>
          Your profile
          <:subtitle>Other people see this when they click your name in the chat.</:subtitle>
        </.header>

        <.form for={@form} id="profile-form" phx-change="validate" phx-submit="save">
          <div class="mb-4 flex items-center gap-4">
            <%= if @user.avatar_id do %>
              <img
                id="current-avatar"
                src={~p"/avatars/#{@user.avatar_id}"}
                alt="Your avatar"
                class="size-20 rounded-full object-cover"
              />
            <% else %>
              <.avatar name={@user.username} class="size-20 text-2xl" />
            <% end %>
            <div class="min-w-0 flex-1 space-y-1 text-sm">
              <label class="font-medium" for={@uploads.avatar.ref}>Avatar</label>
              <.live_file_input upload={@uploads.avatar} class="file-input file-input-sm w-full" />
              <p class="text-xs opacity-60">
                PNG, JPEG or GIF, up to 5 MB. It is cropped to a square.
              </p>
              <p :for={entry <- @uploads.avatar.entries} class="text-xs">
                {entry.client_name}
                <span :for={error <- upload_errors(@uploads.avatar, entry)} class="text-error">
                  – {upload_error(error)}
                </span>
              </p>
              <p :if={@avatar_error} id="avatar-error" class="text-xs text-error">{@avatar_error}</p>
            </div>
          </div>

          <.input
            field={@form[:description]}
            type="textarea"
            label="About you"
            rows="4"
            placeholder="A few words about yourself (up to 500 characters)"
          />

          <.button variant="primary" phx-disable-with="Saving…">Save profile</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    user = socket.assigns.current_scope.user

    {:ok,
     socket
     |> assign(:page_title, "Your profile")
     |> assign(:avatar_error, nil)
     |> assign_user(user)
     |> allow_upload(:avatar,
       accept: ~w(.png .jpg .jpeg .gif),
       max_entries: 1,
       max_file_size: 5_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"user" => params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user_profile(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
  end

  def handle_event("save", %{"user" => params}, socket) do
    with {:ok, user} <- Accounts.update_user_profile(socket.assigns.user, params),
         {:ok, user} <- save_avatar(socket, user) do
      {:noreply,
       socket
       |> put_flash(:info, "Profile saved.")
       |> assign(:avatar_error, nil)
       |> assign_user(user)}
    else
      {:error, :invalid_image} ->
        {:noreply,
         assign(socket, :avatar_error, "The uploaded file could not be read as an image.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :user))}
    end
  end

  defp save_avatar(socket, user) do
    images =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case images do
      [image] -> Accounts.update_user_avatar(user, image)
      [] -> {:ok, user}
    end
  end

  # Keep the header (which reads the scope) in sync with the saved profile.
  defp assign_user(socket, user) do
    socket
    |> assign(:user, user)
    |> assign(:current_scope, %{socket.assigns.current_scope | user: user})
    |> assign(:form, to_form(Accounts.change_user_profile(user), as: :user))
  end

  defp upload_error(:too_large), do: "larger than 5 MB"
  defp upload_error(:not_accepted), do: "not a PNG, JPEG or GIF"
  defp upload_error(:too_many_files), do: "only one image at a time"
  defp upload_error(error), do: inspect(error)
end
