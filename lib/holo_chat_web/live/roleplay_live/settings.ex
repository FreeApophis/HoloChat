defmodule HoloChatWeb.RoleplayLive.Settings do
  use HoloChatWeb, :live_view

  alias HoloChat.{Characters, Rooms, Scenarios}

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

        <section id="scenario" class="space-y-4">
          <h2 class="text-lg font-semibold">Scenario</h2>
          <div
            id="current-scenario"
            class="flex items-center gap-4 rounded-xl border border-base-300 p-3"
          >
            <div class="aspect-video w-28 shrink-0 overflow-hidden rounded-lg bg-gradient-to-br from-sky-500 via-indigo-500 to-fuchsia-500">
              <img
                :if={@room.scenario && @room.scenario.card_image_id}
                src={~p"/avatars/#{@room.scenario.card_image_id}"}
                alt=""
                class="size-full object-cover"
              />
            </div>
            <div class="min-w-0 flex-1">
              <p class="truncate font-semibold">
                {if @room.scenario, do: @room.scenario.title, else: "No scenario"}
              </p>
              <p :if={@room.scenario} class="line-clamp-2 text-sm opacity-70">
                {@room.scenario.topic}
              </p>
            </div>
            <.link
              :if={@room.scenario && Scenarios.can_edit?(@current_scope, @room.scenario)}
              id="edit-scenario-link"
              navigate={~p"/scenarios/#{@room.scenario.id}/edit"}
              class="rounded-lg px-2 py-1 text-xs font-medium opacity-70 transition hover:bg-base-200 hover:opacity-100"
            >
              Edit
            </.link>
          </div>

          <.form
            for={@switch_form}
            id="switch-scenario-form"
            phx-submit="switch_scenario"
            class="flex items-start gap-2"
          >
            <div class="flex-1">
              <.input
                field={@switch_form[:scenario_id]}
                type="select"
                options={@scenario_options}
                aria-label="Next scenario"
              />
            </div>
            <.button data-confirm="Switch scenarios? The cast is replaced, and the characters forget everything that happened so far.">
              Switch
            </.button>
          </.form>
          <p class="-mt-2 text-xs opacity-60">
            Switching announces the new scenario in the chat and casts its suggested characters.
            Browse the <.link navigate={~p"/scenarios"} class="font-medium text-primary">scenario library</.link>.
          </p>
        </section>

        <.form for={@form} id="scene-form" phx-change="validate" phx-submit="save">
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

          <.button variant="primary" phx-disable-with="Saving…">Save settings</.button>
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

          <.cast_editor
            cast={@cast}
            suggestions={@suggestions}
            search_form={@search_form}
            search_results={@search_results}
            tags={scenario_tags(@room)}
          />
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

  @impl true
  def mount(%{"room" => name}, _session, socket) do
    scope = socket.assigns.current_scope
    room = Rooms.get_room(name)

    if room && Rooms.can_manage?(scope, room) do
      {:ok,
       socket
       |> assign(:page_title, "Scene settings")
       |> assign(:scenario_options, Enum.map(Scenarios.list_scenarios(), &{&1.title, &1.id}))
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

    case Rooms.update_room(scope, socket.assigns.room, params) do
      {:ok, room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scene saved.")
         |> push_navigate(to: ~p"/rooms/#{room.name}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :room))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "You are no longer a game master here.")}
    end
  end

  def handle_event("switch_scenario", %{"room" => %{"scenario_id" => id}}, socket) do
    %{current_scope: scope, room: room} = socket.assigns

    case Rooms.switch_scenario(scope, room, id) do
      {:ok, room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Now playing #{room.scenario.title}.")
         |> assign_room(room)}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That scenario no longer exists.")}

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

  defp assign_room(socket, room) do
    socket
    |> assign(:room, room)
    |> assign(:form, to_form(Rooms.change_room(room), as: :room))
    |> assign(:switch_form, to_form(%{"scenario_id" => room.scenario_id}, as: :room))
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

  defp scenario_tags(%{scenario: nil}), do: []
  defp scenario_tags(%{scenario: scenario}), do: scenario.tags
end
