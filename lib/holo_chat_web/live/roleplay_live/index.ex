defmodule HoloChatWeb.RoleplayLive.Index do
  use HoloChatWeb, :live_view

  alias HoloChat.Rooms
  alias HoloChatWeb.Presence

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-0 flex-1 overflow-y-auto">
        <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="flex items-center gap-2 text-2xl font-semibold tracking-tight">
              <.icon name="hero-sparkles" class="size-6 text-primary" /> Role-play
            </h1>
            <p class="mt-1 text-sm opacity-70">
              Scenes run by their game masters. Step in and play a part, or browse the
              <.link
                id="scenarios-link"
                navigate={~p"/scenarios"}
                class="font-medium text-primary hover:underline"
              >
                scenarios
              </.link>
              and <.link
                navigate={~p"/characters"}
                class="font-medium text-primary hover:underline"
              >
                characters
              </.link>.
            </p>
          </div>
          <.link
            :if={@current_scope}
            id="new-room-link"
            navigate={~p"/roleplay/new"}
            class="flex items-center gap-1.5 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-primary-content shadow-sm transition hover:opacity-90"
          >
            <.icon name="hero-plus" class="size-4" /> New scene
          </.link>
        </div>

        <div
          :if={@scenes == []}
          id="no-rooms"
          class="flex flex-col items-center gap-2 rounded-2xl border border-dashed border-base-300 py-16 text-center opacity-70"
        >
          <.icon name="hero-book-open" class="size-8" />
          <p class="text-sm">No scenes yet. Start the first one!</p>
        </div>

        <div id="roleplay-rooms" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <article
            :for={{scenario, rooms} <- @scenes}
            id={"scenario-card-#{scenario.id}"}
            class="group relative flex flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg"
          >
            <div class="relative aspect-video overflow-hidden bg-gradient-to-br from-indigo-500 via-violet-500 to-fuchsia-500">
              <img
                :if={scenario.card_image_id}
                src={~p"/avatars/#{scenario.card_image_id}"}
                alt=""
                class="size-full object-cover transition duration-500 group-hover:scale-105"
              />
              <.icon
                :if={!scenario.card_image_id}
                name="hero-sparkles"
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
              <ul class="mt-2 space-y-1 border-t border-base-300 pt-2">
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
            </div>
          </article>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Presence.subscribe_rooms()

    {:ok,
     socket
     |> assign(:page_title, "Role-play")
     |> assign(:scenes, group_by_scenario(Rooms.list_roleplay_rooms()))
     |> assign(:room_counts, Presence.room_counts())}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :room_counts, Presence.room_counts())}
  end

  # One entry per scenario, ordered by its newest room.
  defp group_by_scenario(rooms) do
    by_scenario = Enum.group_by(rooms, & &1.scenario_id)

    rooms
    |> Enum.uniq_by(& &1.scenario_id)
    |> Enum.map(&{&1.scenario, Map.fetch!(by_scenario, &1.scenario_id)})
  end

  defp online(room_counts, rooms) do
    rooms |> Enum.map(&Map.get(room_counts, &1.name, 0)) |> Enum.sum()
  end
end
