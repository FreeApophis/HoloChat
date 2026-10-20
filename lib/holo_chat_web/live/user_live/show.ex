defmodule HoloChatWeb.UserLive.Show do
  use HoloChatWeb, :live_view

  alias HoloChat.{Accounts, Characters, Rooms, Scenarios}

  @role_labels %{
    admin: "Admin",
    moderator: "Moderator",
    library_editor: "Library editor",
    news_editor: "News editor"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-3xl min-h-0 flex-1 space-y-8 overflow-y-auto py-6">
        <header class="relative overflow-hidden rounded-3xl border border-base-300 bg-base-100 p-6 shadow-sm sm:p-8">
          <div
            class="absolute -top-20 -right-20 size-64 rounded-full bg-gradient-to-br from-sky-500/20 via-indigo-500/20 to-fuchsia-500/20 blur-3xl"
            aria-hidden="true"
          >
          </div>
          <div class="relative flex flex-col items-center gap-5 text-center sm:flex-row sm:text-left">
            <div id="user-avatar" class="shrink-0">
              <.avatar
                name={@profile.username}
                avatar_id={@profile.avatar_id}
                class="size-24 text-3xl ring-4 ring-base-100 shadow-md"
              />
            </div>
            <div class="min-w-0 flex-1">
              <h1 id="user-name" class="text-3xl font-bold tracking-tight">{@profile.username}</h1>
              <p id="user-joined" class="mt-1 text-sm opacity-60">
                Member since {Calendar.strftime(@profile.joined_at, "%B %Y")}
              </p>
              <div
                :if={@profile.roles != []}
                id="user-roles"
                class="mt-3 flex flex-wrap justify-center gap-1.5 sm:justify-start"
              >
                <span
                  :for={role <- @profile.roles}
                  class="rounded-full bg-primary/10 px-2.5 py-0.5 text-xs font-semibold text-primary"
                >
                  {role_label(role)}
                </span>
              </div>
            </div>
          </div>
          <.markdown
            :if={@profile.description}
            id="user-description"
            text={@profile.description}
            class="relative mt-6 leading-relaxed"
          />
          <p :if={!@profile.description} class="relative mt-6 text-sm opacity-60">
            No description yet.
          </p>
        </header>

        <section :if={@rooms != []} id="user-rooms">
          <h2 class="mb-3 text-sm font-semibold tracking-wide uppercase opacity-60">
            Game master of
          </h2>
          <div class="flex flex-wrap gap-2">
            <.link
              :for={room <- @rooms}
              navigate={~p"/rooms/#{room}"}
              class="rounded-full border border-base-300 bg-base-100 px-3 py-1 text-sm font-medium transition hover:-translate-y-0.5 hover:border-primary hover:text-primary"
            >
              #{room}
            </.link>
          </div>
        </section>

        <section :if={@scenarios != []} id="user-scenarios">
          <h2 class="mb-3 text-sm font-semibold tracking-wide uppercase opacity-60">Scenarios</h2>
          <div class="grid gap-3 sm:grid-cols-2">
            <.link
              :for={scenario <- @scenarios}
              navigate={~p"/scenarios" <> "#scenario-#{scenario.id}"}
              class="group flex items-center gap-3 overflow-hidden rounded-xl border border-base-300 bg-base-100 p-2 pr-4 transition hover:-translate-y-0.5 hover:shadow-md"
            >
              <div class="aspect-video w-20 shrink-0 overflow-hidden rounded-lg bg-gradient-to-br from-sky-500 via-indigo-500 to-fuchsia-500">
                <img
                  :if={scenario.card_image_id}
                  src={~p"/avatars/#{scenario.card_image_id}"}
                  alt=""
                  class="size-full object-cover"
                />
              </div>
              <div class="min-w-0">
                <p class="truncate font-semibold">{scenario.title}</p>
                <p :if={scenario.topic} class="truncate text-xs opacity-60">{scenario.topic}</p>
              </div>
            </.link>
          </div>
        </section>

        <section :if={@characters != []} id="user-characters">
          <h2 class="mb-3 text-sm font-semibold tracking-wide uppercase opacity-60">Characters</h2>
          <div class="flex flex-wrap gap-2">
            <.link
              :for={character <- @characters}
              navigate={~p"/characters/#{character.id}"}
              class="flex items-center gap-2 rounded-full border border-base-300 bg-base-100 py-1 pr-3 pl-1 text-sm font-medium transition hover:-translate-y-0.5 hover:border-primary"
            >
              <.avatar name={character.name} avatar_id={character.avatar_id} class="size-7 text-xs" />
              {character.name}
            </.link>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"username" => username}, _session, socket) do
    case Accounts.get_public_profile(username) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "There is no user called #{username}.")
         |> redirect(to: ~p"/")}

      profile ->
        {:ok,
         socket
         |> assign(:page_title, profile.username)
         |> assign(:profile, profile)
         |> assign(:rooms, Rooms.list_mastered_rooms(profile.id))
         |> assign(:scenarios, Scenarios.list_scenarios_by_owner(profile.id))
         |> assign(:characters, Characters.list_characters_by_owner(profile.id))}
    end
  end

  defp role_label(role), do: Map.fetch!(@role_labels, role)
end
