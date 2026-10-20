defmodule HoloChatWeb.RoomLive.Index do
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
              <.icon name="hero-queue-list" class="size-6 text-primary" /> Rooms
            </h1>
            <p class="mt-1 text-sm opacity-70">
              Every room, who runs it and who is there right now.
            </p>
          </div>
          <.form
            for={@filter_form}
            id="channel-filter"
            phx-change="filter"
            phx-submit="filter"
            class="w-full sm:w-72"
          >
            <.input
              field={@filter_form[:query]}
              type="search"
              placeholder="Filter by name, topic or game master"
              autocomplete="off"
              phx-debounce="150"
            />
          </.form>
        </div>

        <div class="overflow-x-auto rounded-2xl border border-base-300 bg-base-100 shadow-sm">
          <table class="w-full text-left text-sm">
            <thead class="border-b border-base-300 bg-base-200/60 text-xs tracking-wide uppercase opacity-70">
              <tr>
                <th class="px-4 py-3 font-semibold">Room</th>
                <th class="px-4 py-3 font-semibold">Topic</th>
                <th class="px-4 py-3 font-semibold">Game masters</th>
                <th class="px-4 py-3 text-right font-semibold">Online</th>
              </tr>
            </thead>
            <tbody id="channels" phx-update="stream" class="divide-y divide-base-300">
              <tr
                :for={{id, channel} <- @streams.channels}
                id={id}
                class="transition-colors hover:bg-base-200/60"
              >
                <td class="px-4 py-3 whitespace-nowrap">
                  <.link
                    navigate={~p"/rooms/#{channel.name}"}
                    class="flex items-center gap-1.5 font-semibold text-primary hover:underline"
                  >
                    <.icon
                      name={if(channel.scenario_title, do: "hero-sparkles", else: "hero-hashtag")}
                      class={[
                        "size-4 shrink-0",
                        if(channel.scenario_title, do: "text-violet-600", else: "opacity-50")
                      ]}
                    /> #{channel.name}
                  </.link>
                </td>
                <td data-role="topic" class="max-w-md px-4 py-3">
                  <span :if={channel.scenario_title} class="font-medium">
                    {channel.scenario_title}
                  </span>
                  <span :if={channel.scenario_title && channel.topic} class="opacity-50">·</span>
                  <.markdown
                    :if={channel.topic}
                    text={channel.topic}
                    class="inline opacity-70 [&>p]:inline"
                  />
                  <span :if={!channel.scenario_title && !channel.topic} class="opacity-40">—</span>
                </td>
                <td data-role="game-masters" class="px-4 py-3">
                  <span :if={channel.game_masters == []} class="opacity-40">—</span>
                  <div :if={channel.game_masters != []} class="flex -space-x-1.5">
                    <.link
                      :for={gm <- channel.game_masters}
                      navigate={~p"/u/#{gm.username}"}
                      title={gm.username}
                      class="rounded-full ring-2 ring-base-100 transition hover:z-10 hover:-translate-y-0.5"
                    >
                      <.avatar name={gm.username} avatar_id={gm.avatar_id} class="size-7 text-xs" />
                    </.link>
                  </div>
                </td>
                <td class="px-4 py-3 text-right">
                  <span
                    data-role="online"
                    class={[
                      "inline-block min-w-7 rounded-full px-2 py-0.5 text-center text-xs font-medium",
                      if(channel.online > 0,
                        do: "bg-emerald-500/15 text-emerald-600",
                        else: "opacity-40"
                      )
                    ]}
                  >
                    {channel.online}
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
          <p
            :if={@empty?}
            id="no-channels"
            class="px-4 py-10 text-center text-sm opacity-60"
          >
            No room matches “{@filter_form[:query].value}”.
          </p>
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
     |> assign(:page_title, "Rooms")
     |> assign(:filter_form, to_form(%{"query" => ""}, as: :filter))
     |> assign(:channels, Rooms.list_channels())
     |> stream_configure(:channels, dom_id: &"channel-#{&1.name}")
     |> show_channels()}
  end

  @impl true
  def handle_event("filter", %{"filter" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:filter_form, to_form(%{"query" => query}, as: :filter))
     |> show_channels()}
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, show_channels(socket)}
  end

  # Busiest rooms first; otherwise most recently active.
  defp show_channels(socket) do
    counts = Presence.room_counts()
    query = socket.assigns.filter_form[:query].value |> String.trim() |> String.downcase()

    channels =
      socket.assigns.channels
      |> Enum.filter(&matches?(&1, query))
      |> Enum.with_index()
      |> Enum.map(fn {channel, index} ->
        {Map.put(channel, :online, Map.get(counts, channel.name, 0)), index}
      end)
      |> Enum.sort_by(fn {channel, index} -> {-channel.online, index} end)
      |> Enum.map(&elem(&1, 0))

    socket
    |> assign(:empty?, channels == [])
    |> stream(:channels, channels, reset: true)
  end

  defp matches?(_channel, ""), do: true

  defp matches?(channel, query) do
    [
      channel.name,
      channel.topic,
      channel.scenario_title | Enum.map(channel.game_masters, & &1.username)
    ]
    |> Enum.any?(&(&1 && String.contains?(String.downcase(&1), query)))
  end
end
