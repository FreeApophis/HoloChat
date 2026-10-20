defmodule HoloChatWeb.CharacterLive.Index do
  use HoloChatWeb, :live_view

  alias HoloChat.Characters

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-0 flex-1 overflow-y-auto">
        <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="flex items-center gap-2 text-2xl font-semibold tracking-tight">
              <.icon name="hero-user-group" class="size-6 text-primary" /> Characters
            </h1>
            <p class="mt-1 text-sm opacity-70">
              A shared library. Game masters cast these characters in their scenes.
            </p>
          </div>
          <div :if={@current_scope} class="flex items-center gap-2">
            <.link
              id="import-card-link"
              navigate={~p"/characters/import"}
              class="flex items-center gap-1.5 rounded-lg border border-base-300 px-3 py-2 text-sm font-medium shadow-sm transition hover:bg-base-200"
            >
              <.icon name="hero-arrow-up-tray" class="size-4" /> Import card
            </.link>
            <.link
              id="new-character-link"
              navigate={~p"/characters/new"}
              class="flex items-center gap-1.5 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-primary-content shadow-sm transition hover:opacity-90"
            >
              <.icon name="hero-plus" class="size-4" /> New character
            </.link>
          </div>
        </div>

        <div :if={@tag} id="tag-filter" class="mb-4 flex items-center gap-2 text-sm">
          <span class="opacity-70">Tagged</span>
          <.tags tags={[@tag]} />
          <.link patch={~p"/characters"} class="text-xs opacity-60 hover:underline">
            Show all
          </.link>
        </div>

        <div
          :if={@characters == []}
          id="no-characters"
          class="flex flex-col items-center gap-2 rounded-2xl border border-dashed border-base-300 py-16 text-center opacity-70"
        >
          <.icon name="hero-user-group" class="size-8" />
          <p class="text-sm">No characters here yet.</p>
        </div>

        <div id="characters" class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          <article
            :for={character <- @characters}
            id={"character-#{character.id}"}
            class="flex gap-3 rounded-2xl border border-base-300 bg-base-100 p-4 shadow-sm transition hover:-translate-y-0.5 hover:shadow-md"
          >
            <.link navigate={~p"/characters/#{character.id}"} class="shrink-0">
              <.avatar
                name={character.name}
                avatar_id={character.avatar_id}
                class="size-14 text-xl"
              />
            </.link>
            <div class="min-w-0 flex-1 space-y-1">
              <.link
                navigate={~p"/characters/#{character.id}"}
                class="block truncate font-semibold hover:underline"
              >
                {character.name}
              </.link>
              <p class="line-clamp-2 text-sm opacity-70">{character.description}</p>
              <.tags tags={character.tags} link />
            </div>
          </article>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Characters")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tag = params["tag"]
    {:noreply, assign(socket, tag: tag, characters: Characters.list_characters(tag: tag))}
  end
end
