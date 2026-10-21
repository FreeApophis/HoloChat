defmodule HoloChatWeb.ScenarioLive.Form do
  use HoloChatWeb, :live_view

  alias HoloChat.{Characters, Scenarios}
  alias HoloChat.Scenarios.Scenario

  @image_kinds [card_image: :card, background_image: :background]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-2xl space-y-10 py-8">
        <.header>
          {@page_title}
          <:subtitle>
            Where and when the story plays, and what is going on. Who takes part belongs to the
            characters, not here.
          </:subtitle>
        </.header>

        <.form for={@form} id="scenario-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:title]} type="text" label="Title" placeholder="Sunset Beach" />
          <.input
            field={@form[:topic]}
            type="text"
            label="Topic"
            placeholder="One line shown on the card and above the chat"
          />
          <.input
            field={@form[:tag_list]}
            type="text"
            label="Tags"
            placeholder="sci-fi, holiday"
          />
          <p class="-mt-1 mb-3 text-xs opacity-60">
            Comma-separated. Characters with the same tags are suggested for the cast.
          </p>
          <.input
            field={@form[:description]}
            type="textarea"
            label="Description"
            rows="8"
            placeholder="Where and when the scene plays, and what is going on. Markdown works."
          />

          <div class="mb-4 grid gap-4 sm:grid-cols-2">
            <.image_upload
              upload={@uploads.card_image}
              label="Card image"
              hint="Shown on cards and when a room switches to this scenario, cropped to 16:9."
              current={@scenario.card_image_id}
            />
            <.image_upload
              upload={@uploads.background_image}
              label="Background"
              hint="Shown behind the chat, cropped to 16:9."
              current={@scenario.background_image_id}
            />
          </div>
          <p :if={@image_error} id="image-error" class="mb-3 text-sm text-error">{@image_error}</p>

          <.button variant="primary" phx-disable-with="Saving…">Save scenario</.button>
        </.form>

        <section :if={@scenario.id} id="scenario-cast" class="space-y-4">
          <div>
            <h2 class="text-lg font-semibold">Suggested cast</h2>
            <p class="text-sm opacity-70">
              Characters from the
              <.link navigate={~p"/characters"} class="font-medium text-primary">library</.link>
              who join a room when it starts or switches to this scenario.
            </p>
          </div>

          <.cast_editor
            cast={@cast}
            suggestions={@suggestions}
            search_form={@search_form}
            search_results={@search_results}
            tags={@scenario.tags}
          />
        </section>
      </div>
    </Layouts.app>
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
      <div class="aspect-video overflow-hidden rounded-lg bg-gradient-to-br from-sky-500 via-indigo-500 to-fuchsia-500">
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
  def mount(params, _session, socket) do
    case load_scenario(socket.assigns.live_action, params, socket.assigns.current_scope) do
      {:ok, scenario, title} ->
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
         |> assign(:page_title, title)
         |> assign(:image_error, nil)
         |> assign(:search_form, to_form(%{"query" => ""}, as: :search))
         |> assign(:search_results, [])
         |> assign_scenario(scenario)}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Only its owner can edit this scenario.")
         |> redirect(to: ~p"/scenarios")}
    end
  end

  defp load_scenario(:new, _params, _scope), do: {:ok, %Scenario{}, "New scenario"}

  defp load_scenario(:edit, %{"id" => id}, scope) do
    with %Scenario{} = scenario <- Scenarios.get_scenario(id),
         true <- Scenarios.can_edit?(scope, scenario) do
      {:ok, scenario, "Edit #{scenario.title}"}
    else
      _missing_or_not_allowed -> :error
    end
  end

  @impl true
  def handle_event("validate", %{"scenario" => params}, socket) do
    changeset =
      socket.assigns.scenario
      |> Scenarios.change_scenario(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"scenario" => params}, socket) do
    with {:ok, scenario} <- save_scenario(socket.assigns.live_action, socket, params),
         {:ok, scenario} <- save_images(socket, scenario) do
      {:noreply, saved(socket, socket.assigns.live_action, scenario)}
    else
      {:error, :invalid_image} ->
        {:noreply,
         assign(socket, :image_error, "An uploaded file could not be read as an image.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't edit this scenario.")}
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

  defp save_scenario(:new, socket, params),
    do: Scenarios.create_scenario(socket.assigns.current_scope, params)

  defp save_scenario(:edit, socket, params),
    do: Scenarios.update_scenario(socket.assigns.current_scope, socket.assigns.scenario, params)

  # A new scenario goes on to its edit page, where the cast is picked.
  defp saved(socket, :new, scenario) do
    socket
    |> put_flash(:info, "Scenario created. Now pick its suggested cast.")
    |> push_navigate(to: ~p"/scenarios/#{scenario.id}/edit")
  end

  defp saved(socket, :edit, scenario) do
    socket
    |> put_flash(:info, "Scenario saved.")
    |> assign_scenario(scenario)
  end

  # Each uploaded image replaces the scenario's current one; the scenario
  # returned by the last update carries all new image ids.
  defp save_images(socket, scenario) do
    scope = socket.assigns.current_scope

    Enum.reduce_while(@image_kinds, {:ok, scenario}, fn {upload, kind}, {:ok, scenario} ->
      images =
        consume_uploaded_entries(socket, upload, fn %{path: path}, _entry ->
          {:ok, File.read!(path)}
        end)

      result =
        case images do
          [image] -> Scenarios.update_scenario_image(scope, scenario, kind, image)
          [] -> {:ok, scenario}
        end

      case result do
        {:ok, scenario} -> {:cont, {:ok, scenario}}
        error -> {:halt, error}
      end
    end)
  end

  defp change_cast(socket, action, id) do
    %{current_scope: scope, scenario: scenario} = socket.assigns

    case apply(Scenarios, action, [scope, scenario, String.to_integer(id)]) do
      {:ok, _scenario} ->
        {:noreply, socket |> assign_cast() |> assign_search_results()}

      {:error, :not_found} ->
        {:noreply,
         socket |> put_flash(:error, "That character no longer exists.") |> assign_cast()}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You can't edit this scenario.")}
    end
  end

  defp assign_scenario(socket, scenario) do
    socket
    |> assign(:scenario, scenario)
    |> assign(:form, to_form(Scenarios.change_scenario(scenario)))
    |> assign_cast()
  end

  defp assign_cast(%{assigns: %{scenario: %Scenario{id: nil}}} = socket) do
    assign(socket, cast: [], suggestions: [])
  end

  defp assign_cast(socket) do
    scenario = socket.assigns.scenario

    socket
    |> assign(:cast, Scenarios.list_cast(scenario))
    |> assign(:suggestions, Scenarios.suggest_cast(scenario))
  end

  defp assign_search_results(socket) do
    cast_ids = Enum.map(socket.assigns.cast, & &1.id)
    query = socket.assigns.search_form[:query].value || ""
    assign(socket, :search_results, Characters.search_characters(query, cast_ids))
  end

  defp upload_error(:too_large), do: "Larger than 8 MB."
  defp upload_error(:not_accepted), do: "Not a PNG, JPEG or GIF."
  defp upload_error(:too_many_files), do: "Only one image at a time."
  defp upload_error(error), do: inspect(error)
end
