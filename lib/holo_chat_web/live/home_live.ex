defmodule HoloChatWeb.HomeLive do
  use HoloChatWeb, :live_view

  alias HoloChat.{News, Rooms}

  @features [
    %{
      icon: "hero-user-group",
      title: "Meet different people",
      text:
        "Real players from everywhere, and AI characters with their own personalities, who remember the scene and answer in character."
    },
    %{
      icon: "hero-sparkles",
      title: "Scenes with a game master",
      text:
        "Game masters set the stage, pick the cast and keep the story moving. You just step in and play your part."
    },
    %{
      icon: "hero-bolt",
      title: "Live, all the way",
      text:
        "Messages appear the moment they are written. See who is around, who is typing, and jump between rooms without missing a beat."
    }
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div id="landing" class="-mx-4 -my-4 min-h-0 flex-1 overflow-y-auto px-4 py-4 sm:-mx-6 sm:px-6">
        <section
          id="landing-hero"
          class="relative isolate overflow-hidden rounded-3xl bg-slate-950 px-6 py-16 text-white shadow-xl sm:px-12 sm:py-24"
        >
          <div
            class="absolute inset-0 -z-10 bg-[linear-gradient(to_right,rgb(56_189_248/0.12)_1px,transparent_1px),linear-gradient(to_bottom,rgb(56_189_248/0.12)_1px,transparent_1px)] bg-[size:40px_40px] [mask-image:radial-gradient(ellipse_at_center,black_30%,transparent_75%)]"
            aria-hidden="true"
          >
          </div>
          <div
            class="absolute -top-24 -left-24 -z-10 size-96 rounded-full bg-cyan-500/30 blur-3xl"
            aria-hidden="true"
          >
          </div>
          <div
            class="absolute -right-24 -bottom-32 -z-10 size-96 rounded-full bg-fuchsia-600/30 blur-3xl"
            aria-hidden="true"
          >
          </div>

          <p class="inline-flex items-center gap-2 rounded-full border border-cyan-300/30 bg-cyan-300/10 px-3 py-1 text-xs font-medium tracking-wide text-cyan-200 uppercase">
            <span class="size-1.5 animate-pulse rounded-full bg-cyan-300"></span> Stories are live
          </p>
          <h1 class="mt-6 max-w-3xl text-4xl font-bold tracking-tight text-balance sm:text-6xl">
            Step into the story.
            <span class="bg-gradient-to-r from-cyan-300 via-sky-300 to-fuchsia-400 bg-clip-text text-transparent">Anywhere you can imagine.</span>
          </h1>
          <p class="mt-6 max-w-2xl text-lg text-pretty text-slate-300">
            HoloChat is your gateway to living stories. Stroll a tropical beach, haggle in a
            fantasy bazaar or stand watch on a frontier station, together with real people and
            AI characters who play along.
          </p>

          <div class="mt-10 flex flex-wrap items-center gap-3">
            <.link
              :if={!@current_scope}
              id="landing-signup"
              navigate={~p"/users/register"}
              class="group inline-flex items-center gap-2 rounded-xl bg-white px-5 py-3 font-semibold text-slate-900 shadow-lg shadow-cyan-500/20 transition hover:-translate-y-0.5 hover:shadow-cyan-400/40"
            >
              Create your free account
              <.icon
                name="hero-arrow-right"
                class="size-4 transition-transform group-hover:translate-x-0.5"
              />
            </.link>
            <.link
              :if={@current_scope}
              id="landing-roleplay"
              navigate={~p"/scenarios"}
              class="group inline-flex items-center gap-2 rounded-xl bg-white px-5 py-3 font-semibold text-slate-900 shadow-lg shadow-cyan-500/20 transition hover:-translate-y-0.5 hover:shadow-cyan-400/40"
            >
              <.icon name="hero-sparkles" class="size-4 text-violet-600" /> Find a scene
              <.icon
                name="hero-arrow-right"
                class="size-4 transition-transform group-hover:translate-x-0.5"
              />
            </.link>
            <.link
              id="landing-enter"
              navigate={~p"/rooms/lobby"}
              class="inline-flex items-center gap-2 rounded-xl border border-white/20 bg-white/5 px-5 py-3 font-semibold text-white backdrop-blur transition hover:-translate-y-0.5 hover:bg-white/10"
            >
              <.icon name="hero-chat-bubble-left-right" class="size-4" />
              {if @current_scope, do: "Enter the lobby", else: "Peek into the lobby"}
            </.link>
          </div>
        </section>

        <section :if={@news != []} id="landing-news" class="mt-16">
          <div class="flex flex-wrap items-end justify-between gap-4">
            <div class="max-w-2xl">
              <h2 class="text-sm font-semibold tracking-wide text-primary uppercase">News</h2>
              <p class="mt-2 text-3xl font-bold tracking-tight text-balance">
                What's been happening
              </p>
            </div>
            <.link
              id="landing-all-news"
              navigate={~p"/news"}
              class="group inline-flex items-center gap-1 text-sm font-medium text-primary"
            >
              All news
              <.icon
                name="hero-arrow-right"
                class="size-4 transition-transform group-hover:translate-x-0.5"
              />
            </.link>
          </div>

          <div class="mt-8 grid gap-4 sm:grid-cols-2">
            <.post_card :for={post <- @news} id={"news-#{post.id}"} post={post} />
          </div>
        </section>

        <section id="landing-destinations" class="mt-16">
          <div class="max-w-2xl">
            <h2 class="text-sm font-semibold tracking-wide text-primary uppercase">Destinations</h2>
            <p class="mt-2 text-3xl font-bold tracking-tight text-balance">
              Your next holiday is one sentence away
            </p>
            <p class="mt-3 opacity-70">
              The scenes people are playing right now. Step in, or let a game master build yours.
            </p>
          </div>

          <div
            :if={@destinations == []}
            id="no-destinations"
            class="mt-8 flex flex-col items-center gap-3 rounded-2xl border border-dashed border-base-300 py-12 text-center"
          >
            <.icon name="hero-map" class="size-8 opacity-60" />
            <p class="text-sm opacity-70">No scene is running yet.</p>
            <.link navigate={~p"/scenarios"} class="text-sm font-medium text-primary">
              Browse the scenarios and start one
            </.link>
          </div>

          <div id="destinations" class="mt-8 grid gap-4 sm:grid-cols-2">
            <article
              :for={%{room: room, players: players} <- @destinations}
              id={"destination-#{room.name}"}
              class="group relative overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm transition hover:-translate-y-1 hover:shadow-lg"
            >
              <div class="relative aspect-video overflow-hidden bg-gradient-to-br from-sky-500 via-indigo-500 to-fuchsia-500">
                <img
                  :if={room.scenario.card_image_id}
                  src={~p"/avatars/#{room.scenario.card_image_id}"}
                  alt=""
                  class="size-full object-cover transition duration-500 group-hover:scale-105"
                />
                <div
                  class="absolute inset-0 bg-gradient-to-t from-slate-950/80 via-slate-950/20 to-transparent"
                  aria-hidden="true"
                >
                </div>
                <p class="absolute top-3 left-3 inline-flex items-center gap-1.5 rounded-full bg-slate-950/60 px-2.5 py-1 text-xs font-medium text-white backdrop-blur">
                  <%= if players > 0 do %>
                    <span class="size-1.5 animate-pulse rounded-full bg-emerald-400"></span>
                    {players} {if players == 1, do: "player", else: "players"} this week
                  <% else %>
                    <span class="size-1.5 rounded-full bg-slate-300"></span> Waiting for players
                  <% end %>
                </p>
                <div class="absolute inset-x-0 bottom-0 p-5 text-white">
                  <p class="text-xs font-semibold tracking-wide uppercase opacity-80">
                    #{room.name}
                  </p>
                  <h3 class="mt-1 text-xl font-semibold tracking-tight">
                    <.link navigate={~p"/rooms/#{room.name}"} class="after:absolute after:inset-0">
                      {room.scenario.title}
                    </.link>
                  </h3>
                </div>
              </div>
              <p :if={room.scenario.topic} class="p-5 text-sm leading-relaxed opacity-75">
                {room.scenario.topic}
              </p>
            </article>
          </div>
        </section>

        <section id="landing-features" class="mt-16 grid gap-6 sm:grid-cols-3">
          <div :for={feature <- @features} class="rounded-2xl bg-base-200 p-6">
            <.icon name={feature.icon} class="size-6 text-primary" />
            <h3 class="mt-3 font-semibold">{feature.title}</h3>
            <p class="mt-2 text-sm leading-relaxed opacity-75">{feature.text}</p>
          </div>
        </section>

        <section
          id="landing-closing"
          class="mt-16 mb-4 rounded-3xl bg-gradient-to-r from-cyan-500 via-sky-600 to-fuchsia-600 px-6 py-12 text-center text-white shadow-lg sm:px-12"
        >
          <h2 class="text-3xl font-bold tracking-tight text-balance">
            Your story starts here.
          </h2>
          <p class="mx-auto mt-3 max-w-xl text-white/85">
            No headset, no download. Just a name and a little imagination.
          </p>
          <.link
            navigate={if(@current_scope, do: ~p"/scenarios", else: ~p"/users/register")}
            class="mt-8 inline-flex items-center gap-2 rounded-xl bg-white px-5 py-3 font-semibold text-slate-900 shadow-md transition hover:-translate-y-0.5 hover:shadow-xl"
          >
            {if @current_scope, do: "Browse the scenes", else: "Join HoloChat"}
            <.icon name="hero-arrow-right" class="size-4" />
          </.link>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Welcome")
     |> assign(:news, News.list_published_posts(2))
     |> assign(:destinations, Rooms.list_destinations(2))
     |> assign(:features, @features)}
  end
end
