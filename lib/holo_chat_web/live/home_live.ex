defmodule HoloChatWeb.HomeLive do
  use HoloChatWeb, :live_view

  @destinations [
    %{
      id: "risa",
      name: "Risa",
      tagline: "Pleasure planet",
      text:
        "Warm surf, endless sunsets and a horga'hn on every nightstand. Take the guided tour, or just get lost at the beach bar.",
      icon: "hero-sun",
      gradient: "from-amber-400 via-orange-500 to-pink-500"
    },
    %{
      id: "eldermere",
      name: "Eldermere",
      tagline: "High fantasy",
      text:
        "Dragons over the mountains, a tavern full of rumours and a quest that won't wait. Sharpen your sword or your wit.",
      icon: "hero-fire",
      gradient: "from-emerald-400 via-teal-500 to-cyan-600"
    },
    %{
      id: "neon-district",
      name: "Neon District",
      tagline: "Cyberpunk noir",
      text:
        "Rain on chrome, a client with a secret and a city that never logs off. Every alley hides a story.",
      icon: "hero-bolt",
      gradient: "from-fuchsia-500 via-violet-600 to-indigo-700"
    },
    %{
      id: "deep-station",
      name: "Deep Station Nine-Eleven",
      tagline: "Far frontier",
      text:
        "The last outpost before the unknown. Strange signals, stranger visitors, and a crew that needs a captain.",
      icon: "hero-rocket-launch",
      gradient: "from-sky-500 via-blue-600 to-slate-800"
    }
  ]

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
            <span class="size-1.5 animate-pulse rounded-full bg-cyan-300"></span> The holodeck is open
          </p>
          <h1 class="mt-6 max-w-3xl text-4xl font-bold tracking-tight text-balance sm:text-6xl">
            Step through the arch.
            <span class="bg-gradient-to-r from-cyan-300 via-sky-300 to-fuchsia-400 bg-clip-text text-transparent">Anywhere you can imagine.</span>
          </h1>
          <p class="mt-6 max-w-2xl text-lg text-pretty text-slate-300">
            HoloChat is your gateway to living stories. Stroll the beaches of Risa, haggle in a
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
              navigate={~p"/roleplay"}
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

        <section id="landing-destinations" class="mt-16">
          <div class="max-w-2xl">
            <h2 class="text-sm font-semibold tracking-wide text-primary uppercase">Destinations</h2>
            <p class="mt-2 text-3xl font-bold tracking-tight text-balance">
              Your next holiday is one sentence away
            </p>
            <p class="mt-3 opacity-70">
              Every room is a world. Pick one of ours, or let a game master build yours.
            </p>
          </div>

          <div class="mt-8 grid gap-4 sm:grid-cols-2">
            <article
              :for={destination <- @destinations}
              id={"destination-#{destination.id}"}
              class="group relative overflow-hidden rounded-2xl border border-base-300 bg-base-100 p-6 shadow-sm transition hover:-translate-y-1 hover:shadow-lg"
            >
              <div
                class={[
                  "absolute -top-16 -right-16 size-48 rounded-full bg-gradient-to-br opacity-20 blur-2xl transition-opacity group-hover:opacity-40",
                  destination.gradient
                ]}
                aria-hidden="true"
              >
              </div>
              <div class={[
                "grid size-12 place-items-center rounded-xl bg-gradient-to-br text-white shadow-md",
                destination.gradient
              ]}>
                <.icon name={destination.icon} class="size-6" />
              </div>
              <p class="mt-4 text-xs font-semibold tracking-wide uppercase opacity-60">
                {destination.tagline}
              </p>
              <h3 class="mt-1 text-xl font-semibold tracking-tight">{destination.name}</h3>
              <p class="mt-2 text-sm leading-relaxed opacity-75">{destination.text}</p>
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
            Computer, begin program.
          </h2>
          <p class="mx-auto mt-3 max-w-xl text-white/85">
            No headset, no download, no safety protocols to disable. Just a name and a little imagination.
          </p>
          <.link
            navigate={if(@current_scope, do: ~p"/roleplay", else: ~p"/users/register")}
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
     |> assign(:destinations, @destinations)
     |> assign(:features, @features)}
  end
end
