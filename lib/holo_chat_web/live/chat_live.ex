defmodule HoloChatWeb.ChatLive do
  use HoloChatWeb, :live_view

  alias HoloChat.{Accounts, Assistant, Characters, Chat, Rooms}
  alias HoloChat.Chat.Message
  alias HoloChatWeb.Presence

  @default_room "lobby"
  @typing_timeout :timer.seconds(3)
  @max_avatars 5
  @room_list_size 20
  @max_restored_tabs 20
  @page_size 50

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex min-h-0 flex-1 flex-col">
        <div class="relative z-10 -mb-px flex items-end gap-1 pl-2">
          <nav
            id="room-tabs"
            phx-hook=".RoomTabs"
            class="flex min-w-0 items-end gap-1 overflow-x-auto [scrollbar-width:none]"
            aria-label="Open rooms"
          >
            <div
              :for={tab <- room_tabs(@open_rooms, @room_counts, @room, @unread)}
              id={"room-tab-#{tab.name}"}
              data-kind={room_kind(@roleplay_rooms, tab.name)}
              class={[
                "group flex shrink-0 items-center rounded-t-xl border border-b-0 text-sm transition-colors",
                if(tab.current?,
                  do: "border-base-300 bg-base-100 font-semibold",
                  else: "border-transparent opacity-70 hover:bg-base-200 hover:opacity-100"
                )
              ]}
            >
              <.link
                patch={room_path(tab.name)}
                aria-current={tab.current? && "page"}
                class="flex items-center gap-1.5 py-2 pr-2 pl-3"
              >
                <.icon
                  name={room_icon(@roleplay_rooms, tab.name)}
                  class={[
                    "size-3.5 shrink-0",
                    if(room_kind(@roleplay_rooms, tab.name) == "roleplay",
                      do: "text-violet-500",
                      else: "opacity-50"
                    )
                  ]}
                />
                <span class={["max-w-36 truncate", tab.unread? && "font-semibold"]}>
                  {tab.name}
                </span>
                <span
                  :if={tab.unread?}
                  id={"tab-unread-#{tab.name}"}
                  class="size-2 shrink-0 rounded-full bg-primary"
                  aria-label="New messages"
                ></span>
                <span
                  :if={tab.online > 0}
                  id={"tab-online-#{tab.name}"}
                  class="shrink-0 rounded-full bg-emerald-500/15 px-1.5 text-xs font-medium text-emerald-600"
                  title={"#{tab.online} online"}
                >
                  {tab.online}
                </span>
              </.link>
              <button
                :if={tab.closable?}
                id={"close-tab-#{tab.name}"}
                type="button"
                phx-click="close_tab"
                phx-value-room={tab.name}
                class={[
                  "mr-1.5 rounded-md p-0.5 opacity-40 transition hover:bg-base-300 hover:opacity-100",
                  !tab.current? && "sm:opacity-0 sm:group-hover:opacity-40"
                ]}
                aria-label={"Close #{tab.name}"}
                title="Close tab"
              >
                <.icon name="hero-x-mark" class="size-3.5" />
              </button>
            </div>
          </nav>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".RoomTabs">
            // The open tabs live in the server process; the browser remembers
            // them across reloads and visits to other pages.
            const KEY = "holochat:tabs"
            export default {
              mounted() {
                let rooms = []
                try { rooms = JSON.parse(localStorage.getItem(KEY)) || [] } catch (_e) {}
                if (Array.isArray(rooms) && rooms.length > 0) {
                  this.pushEventTo(this.el, "restore_tabs", {rooms})
                }
                this.handleEvent("chat:tabs", ({rooms}) => {
                  try { localStorage.setItem(KEY, JSON.stringify(rooms)) } catch (_e) {}
                })
              },
              updated() {
                const current = this.el.querySelector("[aria-current='page']")
                if (current) current.scrollIntoView({block: "nearest", inline: "nearest"})
              }
            }
          </script>

          <div class="relative mb-1 shrink-0">
            <button
              id="room-browser-toggle"
              type="button"
              phx-click={JS.toggle(to: "#room-browser")}
              class="flex items-center rounded-lg p-1.5 opacity-70 transition hover:bg-base-200 hover:opacity-100"
              aria-label="Open a room"
              title="Open a room"
            >
              <.icon name="hero-plus" class="size-4" />
            </button>

            <div
              id="room-browser"
              phx-click-away={JS.hide(to: "#room-browser")}
              phx-window-keydown={JS.hide(to: "#room-browser")}
              phx-key="Escape"
              class="absolute top-full right-0 z-30 mt-1 hidden w-64 rounded-2xl border border-base-300 bg-base-100 p-2 shadow-xl sm:right-auto sm:left-0"
            >
              <.form
                for={@room_form}
                id="room-form"
                phx-submit={JS.push("switch_room") |> JS.hide(to: "#room-browser")}
                class="flex items-center gap-1 p-1"
              >
                <input
                  type="text"
                  name={@room_form[:name].name}
                  value={@room_form[:name].value}
                  placeholder="Join a room…"
                  aria-label="Room name"
                  autocomplete="off"
                  class="min-w-0 flex-1 rounded-lg border border-base-300 bg-base-200 px-3 py-1.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/30"
                />
                <button
                  type="submit"
                  class="rounded-lg p-1.5 text-sm transition hover:bg-base-200"
                  aria-label="Join room"
                >
                  <.icon name="hero-arrow-right" class="size-4" />
                </button>
              </.form>

              <h2 class="px-2 pt-2 pb-1 text-xs font-semibold uppercase tracking-wide opacity-60">
                Active rooms
              </h2>
              <div id="room-list" class="max-h-72 overflow-y-auto" aria-label="Rooms">
                <button
                  :for={room <- room_list(@active_rooms, @room_counts, @room, @unread)}
                  id={"room-link-#{room.name}"}
                  type="button"
                  phx-click={JS.hide(to: "#room-browser") |> JS.patch(room_path(room.name))}
                  aria-current={room.current? && "page"}
                  data-kind={room_kind(@roleplay_rooms, room.name)}
                  class={[
                    "flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm transition-colors",
                    if(room.current?,
                      do: "bg-primary/10 font-semibold text-primary",
                      else: "hover:bg-base-200"
                    )
                  ]}
                >
                  <.icon
                    name={room_icon(@roleplay_rooms, room.name)}
                    class="size-3.5 shrink-0 opacity-50"
                  />
                  <span class={["min-w-0 flex-1 truncate", room.unread? && "font-semibold"]}>
                    {room.name}
                  </span>
                  <span
                    :if={room.unread?}
                    id={"room-unread-#{room.name}"}
                    class="size-2 shrink-0 rounded-full bg-primary"
                    aria-label="New messages"
                  ></span>
                  <span
                    :if={room.online > 0}
                    id={"room-online-#{room.name}"}
                    class="shrink-0 rounded-full bg-emerald-500/15 px-1.5 text-xs font-medium text-emerald-600"
                    title={"#{room.online} online"}
                  >
                    {room.online}
                  </span>
                </button>
              </div>

              <.link
                id="roleplay-link"
                navigate={~p"/roleplay"}
                class="mt-2 flex items-center gap-2 rounded-lg bg-gradient-to-r from-violet-500/10 to-fuchsia-500/10 px-2 py-1.5 text-sm font-medium text-violet-600 transition hover:from-violet-500/20 hover:to-fuchsia-500/20"
              >
                <.icon name="hero-sparkles" class="size-4 shrink-0" /> Role-play scenes
              </.link>
            </div>
          </div>
        </div>

        <div class="relative isolate flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm">
          <%!-- Behind all content: -z-10 inside the isolated stacking context --%>
          <div
            :if={@scene && @scene.background_image_id}
            id="scene-background"
            class="pointer-events-none absolute inset-0 -z-10 bg-cover bg-center"
            style={"background-image: url('#{~p"/avatars/#{@scene.background_image_id}"}')"}
          >
            <div class="absolute inset-0 bg-gradient-to-b from-base-100/70 via-base-100/80 to-base-100/90">
            </div>
          </div>

          <div
            :if={@scene}
            id="scene-header"
            class="border-b border-base-300/70 bg-base-100/40 px-4 py-3 backdrop-blur-sm"
          >
            <div class="flex items-start gap-3">
              <div class="min-w-0 flex-1">
                <h2 id="scene-title" class="flex items-center gap-2 text-lg font-semibold">
                  <.icon name="hero-sparkles" class="size-5 text-violet-500" />
                  <span class="truncate">{@scene.title}</span>
                </h2>

                <p :if={@scene.topic} id="scene-topic" class="text-sm opacity-75">
                  {@scene.topic}
                </p>
                <div
                  :if={@cast != []}
                  id="scene-cast"
                  class="mt-2 flex flex-wrap items-center gap-1.5"
                  aria-label="Cast"
                >
                  <button
                    :for={character <- @cast}
                    type="button"
                    phx-click="show_profile"
                    phx-value-character-id={character.id}
                    data-character-id={character.id}
                    title={character.name}
                    class="flex items-center gap-1.5 rounded-full bg-base-100/70 py-0.5 pr-2.5 pl-0.5 text-xs font-medium shadow-sm ring-1 ring-base-300/70 transition hover:bg-base-100"
                  >
                    <.avatar
                      name={character.name}
                      avatar_id={character.avatar_id}
                      class="size-6 text-[0.65rem]"
                    />
                    {character.name}
                  </button>
                </div>
              </div>

              <button
                :if={@scene.scenario}
                id="show-scenario"
                type="button"
                phx-click="toggle_scenario"
                aria-expanded={to_string(@show_scenario?)}
                class="flex items-center gap-1 rounded-lg px-2 py-1 text-sm transition hover:bg-base-200/70"
              >
                <.icon name="hero-book-open" class="size-4" /> Scenario
              </button>

              <.link
                :if={@can_manage_scene?}
                id="scene-settings-link"
                navigate={~p"/rooms/#{@room}/settings"}
                class="rounded-lg p-1.5 transition hover:bg-base-200/70"
                aria-label="Scene settings"
                title="Scene settings"
              >
                <.icon name="hero-cog-6-tooth" class="size-5" />
              </.link>
            </div>
            <.markdown
              :if={@show_scenario? && @scene.scenario}
              id="scenario"
              text={@scene.scenario}
              class="mt-2 max-h-48 overflow-y-auto rounded-lg bg-base-100/70 p-3 text-sm leading-relaxed"
            />
          </div>

          <div class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-3">
            <div class="flex items-center gap-3">
              <h1 id="room-title" class="flex items-center gap-1 text-base font-semibold">
                <.icon name="hero-hashtag" class="size-4 opacity-60" /> {@room}
              </h1>

              <div
                id="online-users"
                class="flex items-center gap-2"
                title={online_summary(@online_names, @guest_count)}
              >
                <div class="flex -space-x-1.5">
                  <button
                    :for={person <- Enum.take(@online_people, @max_avatars)}
                    type="button"
                    phx-click="show_profile"
                    phx-value-user-id={person.user_id}
                    phx-value-persona-id={person.persona_id}
                    phx-value-character-id={person.character_id}
                    data-user-id={person.user_id}
                    data-persona-id={person.persona_id}
                    data-character-id={person.character_id}
                    title={person.name}
                    class="rounded-full ring-2 ring-base-100 transition hover:z-10 hover:scale-110"
                  >
                    <.avatar
                      name={person.name}
                      avatar_id={person.avatar_id}
                      assistant={person.assistant}
                      class="size-6 text-[0.65rem]"
                    />
                  </button>
                </div>

                <span id="online-count" class="flex items-center gap-1.5 text-xs opacity-70">
                  <span class="size-2 animate-pulse rounded-full bg-emerald-500"></span> {length(
                    @online_names
                  ) + @guest_count} online
                </span>
              </div>
            </div>
          </div>

          <div
            id="message-scroller"
            phx-hook=".ScrollToBottom"
            class="flex min-h-0 flex-1 flex-col overflow-y-auto px-4 py-4 [overflow-anchor:none]"
          >
            <div class="pb-2 text-center text-xs">
              <button
                :if={@more_messages?}
                id="load-older"
                phx-click="load_older"
                phx-disable-with="Loading…"
                class="rounded-full border border-base-300 px-3 py-1 opacity-70 transition hover:bg-base-200 hover:opacity-100"
              >
                Load older messages
              </button>

              <p :if={!@more_messages? && @has_messages?} id="history-start" class="opacity-50">
                This is the beginning of #{@room}.
              </p>
            </div>

            <div
              :if={!@has_messages?}
              id="messages-empty"
              class="flex flex-1 flex-col items-center justify-center gap-2 text-center opacity-60"
            >
              <.icon name="hero-sparkles" class="size-8" />
              <p class="text-sm">No messages in #{@room} yet. Say hi!</p>
            </div>

            <div
              id="messages"
              phx-update="stream"
              phx-viewport-top={@more_messages? && "load_older"}
              class="space-y-1"
            >
              <div
                :for={{id, message} <- @streams.messages}
                id={id}
                class="group flex gap-3 rounded-xl px-2 py-1.5 transition-colors hover:bg-base-200/60"
              >
                <% author = author(message, @personas, @characters) %>
                <button
                  type="button"
                  phx-click={author.profile? && "show_profile"}
                  phx-value-user-id={message.user_id}
                  phx-value-persona-id={message.persona_id}
                  phx-value-character-id={message.character_id}
                  class={["h-fit shrink-0 rounded-full", author.profile? && "cursor-pointer"]}
                  aria-label={"Profile of #{author.name}"}
                >
                  <.avatar
                    name={author.name}
                    avatar_id={author.avatar_id}
                    assistant={message.from_assistant}
                  />
                </button>

                <div class="min-w-0">
                  <div class="flex items-baseline gap-2">
                    <button
                      type="button"
                      data-role="author"
                      phx-click={author.profile? && "show_profile"}
                      phx-value-user-id={message.user_id}
                      phx-value-persona-id={message.persona_id}
                      phx-value-character-id={message.character_id}
                      class={["text-sm font-semibold", author.profile? && "hover:underline"]}
                    >
                      {author.name}
                    </button>

                    <span
                      :if={message.from_assistant}
                      data-role="assistant-badge"
                      class="rounded bg-violet-500/15 px-1 text-[0.65rem] font-semibold tracking-wide text-violet-600"
                    >
                      AI
                    </span>

                    <time
                      id={"message-time-#{message.id}"}
                      datetime={DateTime.to_iso8601(message.inserted_at)}
                      title={Calendar.strftime(message.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
                      phx-hook=".LocalTime"
                      phx-update="ignore"
                      class="text-xs opacity-50"
                    >
                      {Calendar.strftime(message.inserted_at, "%H:%M")}
                    </time>
                  </div>

                  <.markdown
                    text={message.body}
                    data-role="message-body"
                    class="text-sm leading-relaxed"
                  />
                </div>
              </div>
            </div>
          </div>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToBottom">
            // Keeps the message list pinned to the newest message while the reader is
            // at the bottom, and keeps the visible messages still when older ones are
            // inserted above them.
            export default {
              mounted() {
                this.messages = this.el.querySelector("#messages")
                this.scroll()
                this.firstMessage = this.messages.firstElementChild
                this.observer = new MutationObserver(() => this.onMessagesChanged())
                this.observer.observe(this.messages, {childList: true})
                this.el.addEventListener("scroll", () => this.remember())
                this.handleEvent("chat:room-entered", () => this.scroll())
              },
              destroyed() { this.observer.disconnect() },
              onMessagesChanged() {
                const first = this.messages.firstElementChild
                if (this.nearBottom) {
                  this.scroll()
                } else if (first !== this.firstMessage) {
                  this.el.scrollTop = this.top + (this.el.scrollHeight - this.height)
                }
                this.firstMessage = first
                this.remember()
              },
              remember() {
                const el = this.el
                this.top = el.scrollTop
                this.height = el.scrollHeight
                this.nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80
              },
              scroll() { this.el.scrollTop = this.el.scrollHeight; this.remember() }
            }
          </script>

          <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalTime">
            // Rewrites a server-rendered UTC <time> in the viewer's own time zone:
            // just the time for today, otherwise date and time.
            export default {
              mounted() {
                const date = new Date(this.el.getAttribute("datetime"))
                const now = new Date()
                const sameDay = date.toDateString() === now.toDateString()
                const sameYear = date.getFullYear() === now.getFullYear()
                const time = {hour: "2-digit", minute: "2-digit"}
                const options = sameDay ? time
                  : sameYear ? {...time, month: "short", day: "numeric"}
                  : {...time, year: "numeric", month: "short", day: "numeric"}

                this.el.textContent = date.toLocaleString(undefined, options)
                this.el.title = date.toLocaleString(undefined, {dateStyle: "full", timeStyle: "long"})
              }
            }
          </script>

          <div
            id="typing-indicator"
            class="flex h-6 items-center gap-2 px-5 text-xs opacity-70"
            aria-live="polite"
          >
            <%= if @typing_names != [] do %>
              <span class="flex items-center gap-0.5" aria-hidden="true">
                <span class="size-1 animate-bounce rounded-full bg-current [animation-delay:-0.3s]"></span>
                <span class="size-1 animate-bounce rounded-full bg-current [animation-delay:-0.15s]"></span>
                <span class="size-1 animate-bounce rounded-full bg-current"></span>
              </span>
              <span>{typing_text(@typing_names)}</span>
            <% end %>
          </div>

          <.form
            :if={@current_scope}
            for={@form}
            id="message-form"
            phx-change="validate"
            phx-submit="send"
            class="flex gap-2 border-t border-base-300 px-3 pt-3"
          >
            <div class="flex-1">
              <.input
                field={@form[:body]}
                type="text"
                placeholder={"Message ##{@room}"}
                autocomplete="off"
              />
            </div>

            <.button variant="primary" id="send-button" phx-disable-with="Sending…">
              <.icon name="hero-paper-airplane" class="size-4" /> Send
            </.button>
          </.form>

          <div
            :if={!@current_scope}
            id="guest-notice"
            class="flex flex-wrap items-center justify-center gap-x-1 border-t border-base-300 px-4 pt-3 pb-1 text-sm opacity-80"
          >
            <.link navigate={~p"/users/log-in"} class="font-semibold text-primary hover:underline">
              Log in
            </.link>
            or
            <.link navigate={~p"/users/register"} class="font-semibold text-primary hover:underline">
              create an account
            </.link>
            to join the conversation.
          </div>
        </div>
      </div>

      <div
        :if={@profile}
        class="fixed inset-0 z-50 grid place-items-center bg-black/40 p-4"
        phx-window-keydown="close_profile"
        phx-key="Escape"
      >
        <div
          id="profile-card"
          class="relative w-full max-w-sm rounded-2xl border border-base-300 bg-base-100 p-6 text-center shadow-xl"
          phx-click-away="close_profile"
          role="dialog"
          aria-label={"Profile of #{@profile.name}"}
        >
          <button
            id="close-profile"
            type="button"
            phx-click="close_profile"
            class="absolute top-3 right-3 rounded-lg p-1 opacity-60 transition hover:bg-base-200 hover:opacity-100"
            aria-label="Close"
          >
            <.icon name="hero-x-mark" class="size-5" />
          </button>

          <.avatar
            name={@profile.name}
            avatar_id={@profile.avatar_id}
            assistant={@profile.assistant}
            class="mx-auto size-24 text-3xl"
          />
          <h2 class="mt-3 flex items-center justify-center gap-2 text-lg font-semibold">
            {@profile.name}
            <span
              :if={@profile.assistant}
              data-role="assistant-badge"
              class="rounded bg-violet-500/15 px-1 text-xs font-semibold tracking-wide text-violet-600"
            >
              AI
            </span>
          </h2>
          <.markdown
            :if={@profile.description}
            text={@profile.description}
            class="mt-2 text-left text-sm opacity-80"
          />
          <p :if={!@profile.description} class="mt-2 text-sm opacity-60">No description yet.</p>
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Chat.subscribe_rooms()
      Presence.subscribe_rooms()
      Assistant.subscribe()
    end

    {:ok,
     socket
     |> assign(:room, nil)
     |> assign(:roleplay_rooms, Rooms.roleplay_room_names())
     |> assign(scene: nil, cast: [], can_manage_scene?: false, show_scenario?: false)
     |> assign(:room_form, to_form(%{"name" => ""}, as: :room))
     |> assign(:max_avatars, @max_avatars)
     |> assign(:me, presence_meta(socket.assigns.current_scope))
     |> assign(:profile, nil)
     |> assign_personas()
     |> assign(:characters, %{})
     |> assign(:typing_timer, nil)
     |> assign(:unread, MapSet.new())
     |> assign(:open_rooms, [@default_room])
     |> assign(:active_rooms, Chat.list_active_rooms(@room_list_size))
     |> assign(:room_counts, Presence.room_counts())}
  end

  # Rooms are switched with live patches, so this process (and its
  # per-tab state such as unread rooms) lives across room changes.
  @impl true
  def handle_params(params, _uri, socket) do
    %{"room" => room} = params

    cond do
      not Chat.valid_room?(room) ->
        {:noreply,
         socket
         |> put_flash(:error, "Room names may only contain lowercase letters, digits and dashes.")
         |> push_navigate(to: room_path(@default_room))}

      room == socket.assigns.room ->
        {:noreply, socket}

      true ->
        {:noreply, socket |> leave_room() |> enter_room(room)}
    end
  end

  defp leave_room(%{assigns: %{room: nil}} = socket), do: socket

  defp leave_room(socket) do
    %{room: room} = socket.assigns

    if connected?(socket) do
      Chat.unsubscribe(room)
      Rooms.unsubscribe(room)
      Presence.unsubscribe(room)
      Presence.untrack_user(room, socket.id)
    end

    restart_typing_timer(socket, false)
  end

  defp enter_room(socket, room) do
    me = %{socket.assigns.me | typing: false}

    if connected?(socket) do
      Chat.subscribe(room)
      Rooms.subscribe(room)
      Presence.subscribe(room)
      {:ok, _} = Presence.track_user(room, socket.id, me)
      {:ok, _} = Presence.put_room(socket.id, room)
    end

    socket
    |> assign(:room, room)
    |> assign(:page_title, "#" <> room)
    |> assign_scene(Rooms.get_room(room))
    |> assign(:show_scenario?, false)
    |> assign(:me, me)
    |> update(:unread, &MapSet.delete(&1, room))
    |> open_tab(room)
    |> assign(:room_counts, Presence.room_counts())
    |> assign_presence()
    |> assign_message_form(%{})
    |> load_latest_messages()
    |> push_event("chat:room-entered", %{})
  end

  defp load_latest_messages(socket) do
    {messages, more?} = Chat.list_messages_page(socket.assigns.room, nil, @page_size)

    socket
    |> remember_characters(messages)
    |> assign(oldest_message: List.first(messages), more_messages?: more?)
    |> assign(:has_messages?, messages != [])
    |> stream(:messages, messages, reset: true)
  end

  @impl true
  def handle_event("validate", %{"message" => params}, socket) do
    changeset =
      %Message{room: socket.assigns.room}
      |> Chat.change_message(params)
      |> Map.put(:action, :validate)

    typing? = String.trim(params["body"] || "") != ""

    {:noreply,
     socket
     |> assign(:form, to_form(changeset))
     |> set_typing(typing?)}
  end

  def handle_event("send", %{"message" => params}, socket) do
    %{current_scope: scope, room: room} = socket.assigns

    case Chat.create_message(scope, room, params) do
      {:ok, _message} ->
        # The message itself arrives via PubSub; just clear the composer.
        {:noreply, socket |> assign_message_form(%{}) |> set_typing(false)}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Log in to post messages.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  # From the button or from scrolling to the top (phx-viewport-top).
  def handle_event("load_older", _params, %{assigns: %{more_messages?: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("load_older", _params, socket) do
    %{room: room, oldest_message: oldest} = socket.assigns
    {older, more?} = Chat.list_messages_page(room, oldest, @page_size)

    {:noreply,
     socket
     |> remember_characters(older)
     |> assign(oldest_message: List.first(older) || oldest, more_messages?: more?)
     # Inserting newest-first at index 0 leaves them in chronological order.
     |> stream(:messages, Enum.reverse(older), at: 0)}
  end

  def handle_event("show_profile", %{"character-id" => id}, socket) when id != "" do
    {:noreply, assign(socket, :profile, character_profile(id))}
  end

  def handle_event("show_profile", %{"persona-id" => id}, socket) when id != "" do
    {:noreply, assign(socket, :profile, persona_profile(id))}
  end

  def handle_event("show_profile", %{"user-id" => id}, socket) when id != "" do
    {:noreply, assign(socket, :profile, user_profile(id))}
  end

  def handle_event("show_profile", _params, socket), do: {:noreply, socket}

  def handle_event("toggle_scenario", _params, socket),
    do: {:noreply, update(socket, :show_scenario?, &(not &1))}

  def handle_event("close_profile", _params, socket),
    do: {:noreply, assign(socket, :profile, nil)}

  def handle_event("close_tab", %{"room" => @default_room}, socket), do: {:noreply, socket}

  def handle_event("close_tab", %{"room" => room}, socket) do
    %{open_rooms: open_rooms, room: current} = socket.assigns
    remaining = List.delete(open_rooms, room)
    socket = socket |> assign(:open_rooms, remaining) |> push_tabs()

    if room == current do
      # The lobby is never closed, so there always is a tab to the left.
      left = Enum.at(open_rooms, Enum.find_index(open_rooms, &(&1 == room)) - 1)
      {:noreply, push_patch(socket, to: room_path(left))}
    else
      {:noreply, socket}
    end
  end

  # Sent by the RoomTabs hook with the tabs this browser had open before.
  def handle_event("restore_tabs", %{"rooms" => rooms}, socket) when is_list(rooms) do
    restored =
      rooms
      |> Enum.filter(&(is_binary(&1) and Chat.valid_room?(&1)))
      |> Enum.take(@max_restored_tabs)

    open_rooms = Enum.uniq([@default_room | restored] ++ socket.assigns.open_rooms)
    {:noreply, socket |> assign(:open_rooms, open_rooms) |> push_tabs()}
  end

  def handle_event("switch_room", %{"room" => %{"name" => name}}, socket) do
    room = normalize_room(name)

    if Chat.valid_room?(room) do
      {:noreply, push_patch(socket, to: room_path(room))}
    else
      {:noreply, put_flash(socket, :error, "Please enter a room name.")}
    end
  end

  @impl true
  def handle_info({:new_message, %{room: room} = message}, %{assigns: %{room: room}} = socket) do
    {:noreply,
     socket
     |> remember_characters([message])
     |> assign(:has_messages?, true)
     |> stream_insert(:messages, message)}
  end

  # Still in flight from a room we just left.
  def handle_info({:new_message, _message}, socket), do: {:noreply, socket}

  def handle_info({:room_updated, %{name: room} = scene}, %{assigns: %{room: room}} = socket) do
    {:noreply, assign_scene(socket, scene)}
  end

  def handle_info({:room_updated, _scene}, socket), do: {:noreply, socket}

  def handle_info({:room_activity, room, at}, socket) do
    active_rooms =
      [
        %{name: room, last_message_at: at}
        | Enum.reject(socket.assigns.active_rooms, &(&1.name == room))
      ]
      |> Enum.take(@room_list_size)

    unread =
      if room == socket.assigns.room,
        do: socket.assigns.unread,
        else: MapSet.put(socket.assigns.unread, room)

    {:noreply, assign(socket, active_rooms: active_rooms, unread: unread)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", topic: topic}, socket) do
    cond do
      Presence.rooms_topic?(topic) ->
        {:noreply, assign(socket, :room_counts, Presence.room_counts())}

      topic == Presence.topic(socket.assigns.room) ->
        {:noreply, assign_presence(socket)}

      true ->
        {:noreply, socket}
    end
  end

  def handle_info({:assistant_personas_changed}, socket), do: {:noreply, assign_personas(socket)}

  # Other assistant events (status, settings) are handled through presence.
  def handle_info({event, _payload}, socket)
      when event in [:assistant_status, :assistant_settings_changed],
      do: {:noreply, socket}

  def handle_info(:assistant_status_request, socket), do: {:noreply, socket}

  def handle_info(:typing_timeout, socket) do
    {:noreply, set_typing(socket, false)}
  end

  # Updates our presence metadata, but only when it actually changed, so
  # keystrokes don't each produce a presence broadcast. While typing, every
  # keystroke pushes back the timeout that clears the typing state.
  # Guests have no composer; ignore crafted events from them.
  defp set_typing(%{assigns: %{current_scope: nil}} = socket, _typing?), do: socket

  defp set_typing(socket, typing?) do
    me = %{socket.assigns.me | typing: typing?}

    if me != socket.assigns.me do
      Presence.update_user(socket.assigns.room, socket.id, me)
    end

    socket
    |> assign(:me, me)
    |> restart_typing_timer(typing?)
  end

  defp restart_typing_timer(socket, typing?) do
    if timer = socket.assigns.typing_timer, do: Process.cancel_timer(timer)
    timer = if typing?, do: Process.send_after(self(), :typing_timeout, @typing_timeout)
    assign(socket, :typing_timer, timer)
  end

  defp assign_presence(socket) do
    users = Presence.list_users(socket.assigns.room)
    names = Enum.map(users, fn {_key, meta} -> meta.name end)

    online_people =
      for {_key, %{name: name} = meta} <- users, name != nil, uniq: true do
        %{
          name: name,
          avatar_id: meta[:avatar_id],
          user_id: meta[:user_id],
          persona_id: meta[:persona_id],
          character_id: meta[:character_id],
          assistant: meta[:assistant] == true
        }
      end

    typing_names =
      for {key, %{typing: true} = meta} <- users, key != socket.id, uniq: true do
        meta.name || "Someone"
      end

    socket
    |> assign(:online_names, names |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort())
    |> assign(:online_people, online_people |> Enum.uniq_by(& &1.name) |> Enum.sort_by(& &1.name))
    |> assign(:guest_count, Enum.count(names, &is_nil/1))
    |> assign(:typing_names, Enum.sort(typing_names))
  end

  # What others see of this view in presence. Guests have no name.
  defp presence_meta(%{user: user}) do
    %{name: user.username, typing: false, avatar_id: user.avatar_id, user_id: user.id}
  end

  defp presence_meta(_guest), do: %{name: nil, typing: false}

  defp user_profile(id) do
    case Accounts.get_user_profile(id) do
      nil ->
        nil

      profile ->
        %{
          name: profile.username,
          avatar_id: profile.avatar_id,
          description: profile.description,
          assistant: false
        }
    end
  end

  defp character_profile(id) do
    case Characters.get_character(id) do
      nil ->
        nil

      character ->
        %{
          name: character.name,
          avatar_id: character.avatar_id,
          description: character.description,
          assistant: false
        }
    end
  end

  # Only public fields: never the system prompt.
  defp persona_profile(id) do
    case Assistant.get_persona(id) do
      nil ->
        nil

      persona ->
        %{
          name: persona.name,
          avatar_id: persona.avatar_id,
          description: persona.description,
          assistant: true
        }
    end
  end

  # The scene of a role-play room; nil for plain chat rooms.
  defp assign_scene(socket, scene) do
    socket
    |> assign(:scene, scene)
    |> assign(:cast, if(scene, do: Rooms.list_cast(scene), else: []))
    |> assign(
      :can_manage_scene?,
      scene != nil and Rooms.can_manage?(socket.assigns.current_scope, scene)
    )
  end

  defp assign_personas(socket) do
    assign(socket, :personas, Map.new(Assistant.list_personas(), &{&1.id, &1}))
  end

  # Loads the cast characters that wrote `messages` and aren't known yet,
  # so their messages show the current name and avatar.
  defp remember_characters(socket, messages) do
    known = socket.assigns.characters

    missing =
      for %{character_id: id} <- messages,
          is_integer(id),
          not Map.has_key?(known, id),
          uniq: true do
        id
      end

    case missing do
      [] ->
        socket

      ids ->
        loaded = Map.new(Characters.list_characters_by_ids(ids), &{&1.id, &1})
        assign(socket, :characters, Map.merge(known, loaded))
    end
  end

  # Who wrote a message, as shown now: people by their current profile,
  # personas by their current avatar, characters by their current sheet.
  # Legacy messages and deleted characters have no profile.
  defp author(%{character_id: id} = message, _personas, characters) when is_integer(id) do
    case characters[id] do
      nil -> %{name: message.username, avatar_id: nil, profile?: false}
      character -> %{name: character.name, avatar_id: character.avatar_id, profile?: true}
    end
  end

  defp author(%{persona_id: id} = message, personas, _characters) when is_integer(id) do
    persona = personas[id]
    %{name: message.username, avatar_id: persona && persona.avatar_id, profile?: persona != nil}
  end

  defp author(%{user: %{avatar_id: avatar_id}} = message, _personas, _characters) do
    %{name: message.username, avatar_id: avatar_id, profile?: true}
  end

  defp author(message, _personas, _characters),
    do: %{name: message.username, avatar_id: nil, profile?: false}

  defp typing_text([name]), do: "#{name} is typing…"
  defp typing_text([a, b]), do: "#{a} and #{b} are typing…"
  defp typing_text(_names), do: "Several people are typing…"

  defp online_summary(names, 0), do: Enum.join(names, ", ")
  defp online_summary(names, 1), do: Enum.join(names ++ ["1 guest"], ", ")
  defp online_summary(names, guests), do: Enum.join(names ++ ["#{guests} guests"], ", ")

  defp assign_message_form(socket, params) do
    changeset = Chat.change_message(%Message{room: socket.assigns.room}, params)
    assign(socket, :form, to_form(changeset))
  end

  defp open_tab(socket, room) do
    if room in socket.assigns.open_rooms do
      socket
    else
      socket |> update(:open_rooms, &(&1 ++ [room])) |> push_tabs()
    end
  end

  defp push_tabs(socket), do: push_event(socket, "chat:tabs", %{rooms: socket.assigns.open_rooms})

  defp room_tabs(open_rooms, room_counts, current, unread) do
    Enum.map(open_rooms, fn name ->
      %{
        name: name,
        online: Map.get(room_counts, name, 0),
        unread?: MapSet.member?(unread, name),
        current?: name == current,
        closable?: name != @default_room
      }
    end)
  end

  defp room_kind(roleplay_rooms, name),
    do: if(MapSet.member?(roleplay_rooms, name), do: "roleplay", else: "chat")

  defp room_icon(roleplay_rooms, name),
    do: if(MapSet.member?(roleplay_rooms, name), do: "hero-sparkles", else: "hero-hashtag")

  # Lobby first, then rooms by latest message, then rooms that only have
  # people in them, and finally the current room if it is none of those.
  defp room_list(active_rooms, room_counts, current, unread) do
    ([@default_room | Enum.map(active_rooms, & &1.name)] ++
       Enum.sort(Map.keys(room_counts)) ++ [current])
    |> Enum.uniq()
    |> Enum.map(fn name ->
      %{
        name: name,
        online: Map.get(room_counts, name, 0),
        unread?: MapSet.member?(unread, name),
        current?: name == current
      }
    end)
  end

  defp room_path(room), do: ~p"/rooms/#{room}"

  defp normalize_room(name) do
    name
    |> String.trim()
    |> String.trim_leading("#")
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
    |> String.slice(0, 32)
  end
end
