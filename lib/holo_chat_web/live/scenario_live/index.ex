defmodule HoloChatWeb.ScenarioLive.Index do
  use HoloChatWeb, :live_view

  alias HoloChat.Scenarios

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-0 flex-1 overflow-y-auto">
        <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="flex items-center gap-2 text-2xl font-semibold tracking-tight">
              <.icon name="hero-map" class="size-6 text-primary" /> Scenarios
            </h1>
            <p class="mt-1 text-sm opacity-70">
              Where and when stories play. Start a room with one, or switch a running scene to another.
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
            </div>
            <div class="flex flex-1 flex-col gap-1 p-4">
              <h2 class="truncate font-semibold">{scenario.title}</h2>
              <p class="line-clamp-2 min-h-10 text-sm opacity-70">{scenario.topic}</p>
              <.tags tags={scenario.tags} />
              <div :if={@current_scope} class="mt-auto flex items-center gap-2 pt-3">
                <.link
                  id={"play-scenario-#{scenario.id}"}
                  navigate={~p"/roleplay/new?scenario=#{scenario.id}"}
                  class="flex items-center gap-1.5 rounded-lg bg-primary/10 px-2.5 py-1.5 text-xs font-medium text-primary transition hover:bg-primary/20"
                >
                  <.icon name="hero-play" class="size-3.5" /> Start a room
                </.link>
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
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Scenarios")
     |> assign(:scenarios, Scenarios.list_scenarios())}
  end
end
