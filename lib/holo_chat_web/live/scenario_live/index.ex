defmodule HoloChatWeb.ScenarioLive.Index do
  use HoloChatWeb, :live_view

  alias HoloChat.{Rooms, Scenarios}
  alias HoloChatWeb.Presence

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-0 flex-1 overflow-y-auto">
        <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="flex items-center gap-2 text-2xl font-semibold tracking-tight">
              <.icon name="hero-sparkles" class="size-6 text-primary" /> Scenarios
            </h1>
            <p class="mt-1 text-sm opacity-70">
              Where and when stories play. Join a scene running in a room, or set up a new one
              and play it with the
              <.link navigate={~p"/characters"} class="font-medium text-primary hover:underline">
                characters
              </.link>
              of your choice.
            </p>
          </div>
          <.link
            :if={@current_scope}
            id="new-scenario-link"
            navigate={~p"/scenarios/new"}
            class="flex items-center gap-1.5 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-primary-content shadow-sm transition hover:opacity-90"
          >
            <.icon name="hero-plus" class="size-4" /> New scenario
          </.link>
        </div>

        <%!-- An admin coming from a chat room starts the scene there. --%>
        <div
          :if={@channel}
          id="scene-channel"
          class="mb-6 flex items-center gap-2 rounded-xl border border-violet-500/30 bg-violet-500/10 px-4 py-3 text-sm"
        >
          <.icon name="hero-sparkles" class="size-4 text-violet-600" />
          <span>Pick a scenario to play in <span class="font-medium">#{@channel}</span>.</span>
        </div>

        <section :if={@waiting != []} id="waiting-scenes" class="mb-8">
          <h2 class="mb-3 text-sm font-semibold tracking-wide uppercase opacity-60">
            Your scenes waiting for a channel
          </h2>
          <ul class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <li :for={scene <- @waiting}>
              <.link
                id={"waiting-scene-#{scene.id}"}
                navigate={~p"/scenes/#{scene.id}/settings"}
                class="flex items-center gap-3 rounded-xl border border-dashed border-base-300 p-3 transition hover:border-primary hover:bg-base-200"
              >
                <div class="aspect-video w-20 shrink-0 overflow-hidden rounded-lg bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-500">
                  <img
                    :if={scene.scenario && scene.scenario.card_image_id}
                    src={~p"/avatars/#{scene.scenario.card_image_id}"}
                    alt=""
                    class="size-full object-cover"
                  />
                </div>
                <div class="min-w-0 flex-1">
                  <p class="truncate font-medium">
                    {if scene.scenario, do: scene.scenario.title, else: "No scenario"}
                  </p>
                  <p class="text-xs opacity-60">Cast it, then start it in a channel</p>
                </div>
                <.icon name="hero-chevron-right" class="size-4 opacity-50" />
              </.link>
            </li>
          </ul>
        </section>

        <div
          :if={@scenarios == []}
          id="no-scenarios"
          class="flex flex-col items-center gap-2 rounded-2xl border border-dashed border-base-300 py-16 text-center opacity-70"
        >
          <.icon name="hero-map" class="size-8" />
          <p class="text-sm">No scenarios yet. Write the first one!</p>
        </div>

        <div id="scenarios" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <article
            :for={scenario <- @scenarios}
            id={"scenario-#{scenario.id}"}
            class="group flex flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg"
          >
            <% rooms = Map.get(@rooms, scenario.id, []) %>
            <div class="relative aspect-video overflow-hidden bg-gradient-to-br from-sky-500 via-indigo-500 to-fuchsia-500">
              <img
                :if={scenario.card_image_id}
                src={~p"/avatars/#{scenario.card_image_id}"}
                alt=""
                class="size-full object-cover transition duration-500 group-hover:scale-105"
              />
              <.icon
                :if={!scenario.card_image_id}
                name="hero-map"
                class="absolute inset-0 m-auto size-12 text-white/70"
              />
              <span
                :if={online(@room_counts, rooms) > 0}
                class="absolute top-2 right-2 flex items-center gap-1 rounded-full bg-black/50 px-2 py-0.5 text-xs font-medium text-white backdrop-blur"
              >
                <span class="size-1.5 rounded-full bg-emerald-400"></span>
                {online(@room_counts, rooms)} online
              </span>
            </div>
            <div class="flex flex-1 flex-col gap-1 p-4">
              <h2 class="truncate font-semibold">{scenario.title}</h2>
              <p class="line-clamp-2 min-h-10 text-sm opacity-70">{scenario.topic}</p>
              <.tags tags={scenario.tags} />
              <ul :if={rooms != []} class="mt-2 space-y-1 border-t border-base-300 pt-2">
                <li :for={room <- rooms}>
                  <.link
                    id={"scene-room-#{room.name}"}
                    navigate={~p"/rooms/#{room.name}"}
                    class="flex items-center justify-between gap-2 rounded-lg px-2 py-1.5 text-sm transition hover:bg-base-200"
                  >
                    <span class="flex min-w-0 items-center gap-1.5">
                      <.icon name="hero-arrow-right-end-on-rectangle" class="size-4 opacity-50" />
                      <span class="truncate font-medium">#{room.name}</span>
                    </span>
                    <span
                      :if={Map.get(@room_counts, room.name, 0) > 0}
                      class="flex shrink-0 items-center gap-1 text-xs opacity-70"
                    >
                      <span class="size-1.5 rounded-full bg-emerald-400"></span>
                      {Map.get(@room_counts, room.name)}
                    </span>
                  </.link>
                </li>
              </ul>
              <div :if={@current_scope} class="mt-auto flex items-center gap-2 pt-3">
                <button
                  id={"play-scenario-#{scenario.id}"}
                  type="button"
                  phx-click="play"
                  phx-value-id={scenario.id}
                  phx-disable-with="Creating…"
                  class="flex items-center gap-1.5 rounded-lg bg-primary/10 px-2.5 py-1.5 text-xs font-medium text-primary transition hover:bg-primary/20"
                >
                  <.icon name="hero-play" class="size-3.5" />
                  {if @channel, do: "Play in ##{@channel}", else: "New scene"}
                </button>
                <.link
                  :if={Scenarios.can_edit?(@current_scope, scenario)}
                  id={"edit-scenario-#{scenario.id}"}
                  navigate={~p"/scenarios/#{scenario.id}/edit"}
                  class="flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-xs font-medium opacity-70 transition hover:bg-base-200 hover:opacity-100"
                >
                  <.icon name="hero-pencil-square" class="size-3.5" /> Edit
                </.link>
              </div>
            </div>
          </article>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    if connected?(socket), do: Presence.subscribe_rooms()

    {:ok,
     socket
     |> assign(:page_title, "Scenarios")
     |> assign(:channel, params["room"])
     |> assign(:scenarios, Scenarios.list_scenarios())
     |> assign(:rooms, Enum.group_by(Rooms.list_roleplay_rooms(), & &1.scenario_id))
     |> assign(:waiting, Rooms.list_waiting_scenes(socket.assigns.current_scope))
     |> assign(:room_counts, Presence.room_counts())}
  end

  @impl true
  def handle_event("play", %{"id" => id}, socket) do
    %{current_scope: scope, channel: channel} = socket.assigns

    case Rooms.create_roleplay_room(scope, %{"scenario_id" => id, "name" => channel}) do
      {:ok, %{name: nil} = scene} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scene created. Cast it, then start it in a channel.")
         |> push_navigate(to: ~p"/scenes/#{scene.id}/settings")}

      {:ok, room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scene created. Welcome, game master!")
         |> push_navigate(to: ~p"/rooms/#{room.name}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, put_flash(socket, :error, "Could not create the scene: #{errors(changeset)}.")}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Log in to create a scene.")}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :room_counts, Presence.room_counts())}
  end

  defp online(room_counts, rooms) do
    rooms |> Enum.map(&Map.get(room_counts, &1.name, 0)) |> Enum.sum()
  end

  defp errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(&translate_error/1)
    |> Enum.map_join(", ", fn {field, messages} ->
      "#{Phoenix.Naming.humanize(field)} #{Enum.join(messages, ", ")}"
    end)
  end
end
