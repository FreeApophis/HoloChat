defmodule HoloChatWeb.CharacterLive.Form do
  use HoloChatWeb, :live_view

  alias HoloChat.Characters
  alias HoloChat.Characters.Character

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-2xl overflow-y-auto py-8">
        <.header>
          {@page_title}
          <:subtitle>
            Everything here describes the character. Where and when a story plays
            belongs to the scene, not here.
          </:subtitle>
        </.header>

        <.form for={@form} id="character-form" phx-change="validate" phx-submit="save">
          <div class="mb-4 flex items-center gap-4">
            <.avatar
              name={@form[:name].value}
              avatar_id={@character.avatar_id}
              class="size-20 text-2xl"
            />
            <div class="min-w-0 flex-1 space-y-1 text-sm">
              <label class="font-medium" for={@uploads.avatar.ref}>Avatar</label>
              <.live_file_input upload={@uploads.avatar} class="file-input file-input-sm w-full" />
              <p class="text-xs opacity-60">PNG, JPEG or GIF, up to 5 MB, cropped to a square.</p>
              <p :for={entry <- @uploads.avatar.entries} class="text-xs">
                {entry.client_name}
                <span :for={error <- upload_errors(@uploads.avatar, entry)} class="text-error">
                  – {upload_error(error)}
                </span>
              </p>
              <p :if={@avatar_error} id="avatar-error" class="text-xs text-error">{@avatar_error}</p>
            </div>
          </div>

          <.input field={@form[:name]} type="text" label="Name" />
          <.input
            field={@form[:tag_list]}
            type="text"
            label="Tags"
            placeholder="harry-potter, hogwarts, student"
          />
          <p class="-mt-1 mb-3 text-xs opacity-60">
            Comma-separated. Scenes with the same tags suggest this character.
          </p>
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description"
            rows="5"
            placeholder="Who they are: looks, background, what they want."
          />
          <.input
            field={@form[:personality]}
            type="textarea"
            label="Personality"
            rows="3"
            placeholder="How they think, talk and behave."
          />

          <.button variant="primary" phx-disable-with="Saving…">Save character</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    socket =
      allow_upload(socket, :avatar,
        accept: ~w(.png .jpg .jpeg .gif),
        max_entries: 1,
        max_file_size: 5_000_000
      )

    case load_character(socket.assigns.live_action, params, socket.assigns.current_scope) do
      {:ok, character, title} ->
        {:ok,
         socket
         |> assign(:page_title, title)
         |> assign(:avatar_error, nil)
         |> assign(:character, character)
         |> assign(:form, to_form(Characters.change_character(character)))}

      {:error, path} ->
        {:ok,
         socket
         |> put_flash(:error, "Only its owner can edit this character.")
         |> redirect(to: path)}
    end
  end

  defp load_character(:new, _params, _scope), do: {:ok, %Character{}, "New character"}

  defp load_character(:edit, %{"id" => id}, scope) do
    case Characters.get_character(id) do
      nil -> {:error, ~p"/characters"}
      character -> editable(character, scope)
    end
  end

  defp editable(character, scope) do
    if Characters.can_edit?(scope, character),
      do: {:ok, character, "Edit #{character.name}"},
      else: {:error, ~p"/characters/#{character.id}"}
  end

  @impl true
  def handle_event("validate", %{"character" => params}, socket) do
    changeset =
      socket.assigns.character
      |> Characters.change_character(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"character" => params}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, character} <- save_character(socket.assigns.live_action, socket, params),
         {:ok, character} <- save_avatar(socket, scope, character) do
      {:noreply, push_navigate(socket, to: ~p"/characters/#{character.id}")}
    else
      {:error, :invalid_image} ->
        {:noreply,
         assign(socket, :avatar_error, "The uploaded file could not be read as an image.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't edit this character.")}
    end
  end

  defp save_character(:new, socket, params),
    do: Characters.create_character(socket.assigns.current_scope, params)

  defp save_character(:edit, socket, params),
    do:
      Characters.update_character(
        socket.assigns.current_scope,
        socket.assigns.character,
        params
      )

  defp save_avatar(socket, scope, character) do
    images =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case images do
      [image] -> Characters.update_character_avatar(scope, character, image)
      [] -> {:ok, character}
    end
  end

  defp upload_error(:too_large), do: "larger than 5 MB"
  defp upload_error(:not_accepted), do: "not a PNG, JPEG or GIF"
  defp upload_error(:too_many_files), do: "only one image at a time"
  defp upload_error(error), do: inspect(error)
end
