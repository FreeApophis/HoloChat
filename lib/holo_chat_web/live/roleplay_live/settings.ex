defmodule HoloChatWeb.RoleplayLive.Settings do
  use HoloChatWeb, :live_view

  alias HoloChat.{Characters, Rooms}

  @image_kinds [card_image: :card, background_image: :background]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-2xl space-y-10 overflow-y-auto py-8">
        <.header>
          Scene settings
          <:subtitle>
            For the game masters of
            <.link navigate={~p"/rooms/#{@room.name}"} class="font-medium text-primary">
              #{@room.name}
            </.link>
          </:subtitle>
        </.header>

        <.form for={@form} id="scene-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:title]} type="text" label="Title" />
          <.input field={@form[:topic]} type="text" label="Topic" />
          <.input
            field={@form[:tag_list]}
            type="text"
            label="Tags"
            placeholder="harry-potter, hogwarts"
          />
          <p class="-mt-1 mb-3 text-xs opacity-60">
            Comma-separated. Characters with the same tags are suggested for the cast.
          </p>
          <.input field={@form[:scenario]} type="textarea" label="Scenario" rows="8" />

          <fieldset id="reply-settings" class="mb-4 rounded-xl border border-base-300 p-4">
            <legend class="px-1 text-sm font-semibold">How the cast takes turns</legend>
            <.input
              field={@form[:reply_policy]}
              type="select"
              label="Turns"
              options={[
                {"Natural: named characters answer, otherwise one of the cast", "natural"},
                {"Only when named: characters answer only when addressed", "mention"}
              ]}
            />
            <div class="grid gap-4 sm:grid-cols-2">
              <.input
                field={@form[:reply_delay]}
                type="number"
                label="Wait for quiet (seconds)"
                min="0"
                max="60"
              />
              <.input
                field={@form[:max_ai_turns]}
                type="number"
                label="AI turns in a row"
                min="1"
                max="5"
              />
            </div>
            <p class="text-xs opacity-60">
              Characters wait until the players have been quiet this long. A character who
              names another lets that one answer, up to the number of AI turns in a row.
            </p>
          </fieldset>

          <div class="mb-4 grid gap-4 sm:grid-cols-2">
            <.image_upload
              upload={@uploads.card_image}
              label="Card image"
              hint="Shown on the role-play overview, cropped to 16:9."
              current={@room.card_image_id}
            />
            <.image_upload
              upload={@uploads.background_image}
              label="Background"
              hint="Shown behind the chat, cropped to 16:9."
              current={@room.background_image_id}
            />
          </div>
          <p :if={@image_error} id="image-error" class="mb-3 text-sm text-error">{@image_error}</p>

          <.button variant="primary" phx-disable-with="Saving…">Save scene</.button>
        </.form>

        <section id="cast" class="space-y-4">
          <div>
            <h2 class="text-lg font-semibold">Cast</h2>
            <p class="text-sm opacity-70">
              Characters from the
              <.link navigate={~p"/characters"} class="font-medium text-primary">library</.link>
              who appear in this scene.
            </p>
          </div>

          <ul
            :if={@cast != []}
            id="cast-members"
            class="divide-y divide-base-300 rounded-xl border border-base-300"
          >
            <li
              :for={character <- @cast}
              id={"cast-member-#{character.id}"}
              class="flex items-center gap-3 px-3 py-2"
            >
              <.avatar name={character.name} avatar_id={character.avatar_id} class="size-8 text-xs" />
              <span class="flex-1 text-sm font-medium">{character.name}</span>
              <button
                id={"uncast-#{character.id}"}
                type="button"
                phx-click="uncast"
                phx-value-id={character.id}
                class="rounded-lg px-2 py-1 text-xs opacity-70 transition hover:bg-base-200 hover:opacity-100"
              >
                Remove
              </button>
            </li>
          </ul>
          <p :if={@cast == []} id="cast-empty" class="text-sm opacity-60">
            Nobody is cast yet.
          </p>

          <div :if={@suggestions != []} id="suggested-characters" class="space-y-2">
            <h3 class="text-sm font-semibold">Suggested for this scene</h3>
            <div class="grid gap-2 sm:grid-cols-2">
              <.cast_candidate
                :for={character <- @suggestions}
                id={"suggestion-#{character.id}"}
                character={character}
                matching={@room.tags}
              />
            </div>
          </div>

          <.form for={@search_form} id="cast-search-form" phx-change="search" phx-submit="search">
            <.input
              field={@search_form[:query]}
              type="search"
              placeholder="Find any character by name…"
              autocomplete="off"
              phx-debounce="250"
            />
          </.form>
          <div :if={@search_results != []} id="search-results" class="grid gap-2 sm:grid-cols-2">
            <.cast_candidate
              :for={character <- @search_results}
              id={"search-result-#{character.id}"}
              character={character}
              matching={@room.tags}
            />
          </div>
        </section>

        <section id="game-masters" class="space-y-3">
          <h2 class="text-lg font-semibold">Game masters</h2>
          <ul class="divide-y divide-base-300 rounded-xl border border-base-300">
            <li
              :for={master <- @masters}
              id={"master-#{master.id}"}
              class="flex items-center gap-3 px-3 py-2"
            >
              <.avatar name={master.username} avatar_id={master.avatar_id} class="size-7 text-xs" />
              <span class="flex-1 text-sm font-medium">{master.username}</span>
              <button
                :if={length(@masters) > 1}
                id={"remove-master-#{master.id}"}
                type="button"
                phx-click="remove_master"
                phx-value-id={master.id}
                class="rounded-lg px-2 py-1 text-xs opacity-70 transition hover:bg-base-200 hover:opacity-100"
              >
                Remove
              </button>
            </li>
          </ul>
          <.form
            for={@master_form}
            id="add-master-form"
            phx-submit="add_master"
            class="flex items-start gap-2"
          >
            <div class="flex-1">
              <.input
                field={@master_form[:username]}
                type="text"
                placeholder="Username"
                autocomplete="off"
              />
            </div>
            <.button>Add</.button>
          </.form>
        </section>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :character, :map, required: true
  attr :matching, :list, required: true

  defp cast_candidate(assigns) do
    ~H"""
    <div id={@id} class="flex items-center gap-3 rounded-xl border border-base-300 p-2">
      <.avatar name={@character.name} avatar_id={@character.avatar_id} class="size-9 text-sm" />
      <div class="min-w-0 flex-1">
        <p class="truncate text-sm font-medium">{@character.name}</p>
        <.tags tags={Enum.filter(@character.tags, &(&1 in @matching))} />
      </div>
      <button
        id={"cast-#{@character.id}"}
        type="button"
        phx-click="cast"
        phx-value-id={@character.id}
        class="flex items-center gap-1 rounded-lg bg-primary/10 px-2 py-1 text-xs font-medium text-primary transition hover:bg-primary/20"
      >
        <.icon name="hero-plus" class="size-3.5" /> Cast
      </button>
    </div>
    """
  end

  attr :upload, :any, required: true
  attr :label, :string, required: true
  attr :hint, :string, required: true
  attr :current, :string, default: nil

  defp image_upload(assigns) do
    ~H"""
    <div class="space-y-2 text-sm">
      <label class="font-medium" for={@upload.ref}>{@label}</label>
      <div class="aspect-video overflow-hidden rounded-lg bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-500">
        <%= case @upload.entries do %>
          <% [entry | _] -> %>
            <.live_img_preview entry={entry} class="size-full object-cover" />
          <% [] -> %>
            <img :if={@current} src={~p"/avatars/#{@current}"} alt="" class="size-full object-cover" />
        <% end %>
      </div>
      <.live_file_input upload={@upload} class="file-input file-input-sm w-full" />
      <p class="text-xs opacity-60">{@hint} PNG, JPEG or GIF, up to 8 MB.</p>
      <p :for={entry <- @upload.entries} class="text-xs">
        <span :for={error <- upload_errors(@upload, entry)} class="text-error">
          {upload_error(error)}
        </span>
      </p>
    </div>
    """
  end

  @impl true
  def mount(%{"room" => name}, _session, socket) do
    scope = socket.assigns.current_scope
    room = Rooms.get_room(name)

    if room && Rooms.can_manage?(scope, room) do
      socket =
        Enum.reduce(Keyword.keys(@image_kinds), socket, fn upload, socket ->
          allow_upload(socket, upload,
            accept: ~w(.png .jpg .jpeg .gif),
            max_entries: 1,
            max_file_size: 8_000_000
          )
        end)

      {:ok,
       socket
       |> assign(:page_title, "Scene settings")
       |> assign(:image_error, nil)
       |> assign(:master_form, to_form(%{"username" => ""}, as: :master))
       |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
       |> assign_room(room)
       |> assign(:search_results, [])}
    else
      {:ok,
       socket
       |> put_flash(:error, "Only the game masters can change this scene.")
       |> redirect(to: ~p"/rooms/#{name}")}
    end
  end

  @impl true
  def handle_event("validate", %{"room" => params}, socket) do
    changeset = socket.assigns.room |> Rooms.change_room(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :room))}
  end

  def handle_event("save", %{"room" => params}, socket) do
    scope = socket.assigns.current_scope

    with {:ok, room} <- Rooms.update_room(scope, socket.assigns.room, params),
         {:ok, _room} <- save_images(socket, room) do
      {:noreply,
       socket
       |> put_flash(:info, "Scene saved.")
       |> push_navigate(to: ~p"/rooms/#{room.name}")}
    else
      {:error, :invalid_image} ->
        {:noreply,
         assign(socket, :image_error, "An uploaded file could not be read as an image.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :room))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are no longer a game master here.")}
    end
  end

  def handle_event("cast", %{"id" => id}, socket), do: change_cast(socket, :cast_character, id)

  def handle_event("uncast", %{"id" => id}, socket),
    do: change_cast(socket, :uncast_character, id)

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:search_form, to_form(%{"query" => query}, as: :search))
     |> assign_search_results()}
  end

  def handle_event("add_master", %{"master" => %{"username" => username}}, socket) do
    %{current_scope: scope, room: room} = socket.assigns

    case Rooms.add_game_master(scope, room, username) do
      {:ok, user} ->
        {:noreply,
         socket
         |> put_flash(:info, "#{user.username} is now a game master.")
         |> assign(:master_form, to_form(%{"username" => ""}, as: :master))
         |> assign_masters()}

      {:error, :not_found} ->
        {:noreply,
         assign(
           socket,
           :master_form,
           to_form(%{"username" => username},
             as: :master,
             errors: [username: {"No user with that name", []}]
           )
         )}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are no longer a game master here.")}
    end
  end

  def handle_event("remove_master", %{"id" => id}, socket) do
    %{current_scope: scope, room: room} = socket.assigns

    case Rooms.remove_game_master(scope, room, String.to_integer(id)) do
      :ok ->
        {:noreply, assign_masters(socket)}

      {:error, :last_game_master} ->
        {:noreply, put_flash(socket, :error, "A scene needs at least one game master.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are no longer a game master here.")}
    end
  end

  defp change_cast(socket, action, id) do
    %{current_scope: scope, room: room} = socket.assigns

    case apply(Rooms, action, [scope, room, String.to_integer(id)]) do
      {:ok, _room} ->
        {:noreply, socket |> assign_cast() |> assign_search_results()}

      {:error, :not_found} ->
        {:noreply,
         socket |> put_flash(:error, "That character no longer exists.") |> assign_cast()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are no longer a game master here.")}
    end
  end

  # Each uploaded image replaces the room's current one; the room returned
  # by the last update carries all new image ids.
  defp save_images(socket, room) do
    scope = socket.assigns.current_scope

    Enum.reduce_while(@image_kinds, {:ok, room}, fn {upload, kind}, {:ok, room} ->
      images =
        consume_uploaded_entries(socket, upload, fn %{path: path}, _entry ->
          {:ok, File.read!(path)}
        end)

      result =
        case images do
          [image] -> Rooms.update_room_image(scope, room, kind, image)
          [] -> {:ok, room}
        end

      case result do
        {:ok, room} -> {:cont, {:ok, room}}
        error -> {:halt, error}
      end
    end)
  end

  defp assign_room(socket, room) do
    socket
    |> assign(:room, room)
    |> assign(:form, to_form(Rooms.change_room(room), as: :room))
    |> assign_masters()
    |> assign_cast()
  end

  defp assign_cast(socket) do
    room = socket.assigns.room

    socket
    |> assign(:cast, Rooms.list_cast(room))
    |> assign(:suggestions, Rooms.suggest_cast(room))
  end

  defp assign_search_results(socket) do
    cast_ids = Enum.map(socket.assigns.cast, & &1.id)
    query = socket.assigns.search_form[:query].value || ""
    assign(socket, :search_results, Characters.search_characters(query, cast_ids))
  end

  defp assign_masters(socket) do
    assign(socket, :masters, Rooms.list_game_masters(socket.assigns.room))
  end

  defp upload_error(:too_large), do: "Larger than 8 MB."
  defp upload_error(:not_accepted), do: "Not a PNG, JPEG or GIF."
  defp upload_error(:too_many_files), do: "Only one image at a time."
  defp upload_error(error), do: inspect(error)
end
