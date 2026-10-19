defmodule HoloChatWeb.ChatLive do
  use HoloChatWeb, :live_view

  alias HoloChat.{Accounts, Assistant, Characters, Chat, Rooms, Scenarios}
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
            </div>
          </div>
        </div>

        <div class="relative isolate flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm">
          <%!-- Behind all content: -z-10 inside the isolated stacking context --%>
          <div
            :if={@scenario && @scenario.background_image_id}
            id="scene-background"
            class="pointer-events-none absolute inset-0 -z-10 bg-cover bg-center"
            style={"background-image: url('#{~p"/avatars/#{@scenario.background_image_id}"}')"}
          >
            <div class="absolute inset-0 bg-gradient-to-b from-base-100/70 via-base-100/80 to-base-100/90">
            </div>
          </div>

          <div
            :if={@scenario}
            id="scene-header"
            class="border-b border-base-300/70 bg-base-100/40 px-4 py-3 backdrop-blur-sm"
          >
            <div class="flex items-start gap-3">
              <div class="min-w-0 flex-1">
                <h2 id="scene-title" class="flex items-center gap-2 text-lg font-semibold">
                  <.icon name="hero-sparkles" class="size-5 text-violet-500" />
                  <span class="truncate">{@scenario.title}</span>
                </h2>

                <p :if={@scenario.topic} id="scene-topic" class="text-sm opacity-75">
                  {@scenario.topic}
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
                :if={@scenario.description}
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
              :if={@show_scenario? && @scenario.description}
              id="scenario"
              text={@scenario.description}
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
                    phx-value-cloak-id={person.cloak && person.cloak.id}
                    data-user-id={person.user_id}
                    data-persona-id={person.persona_id}
                    data-character-id={person.character_id}
                    data-cloak-id={person.cloak && person.cloak.id}
                    title={
                      if(person.cloak,
                        do: "#{person.cloak.name} (played by #{person.name})",
                        else: person.name
                      )
                    }
                    class="rounded-full ring-2 ring-base-100 transition hover:z-10 hover:scale-110"
                  >
                    <.cloaked_avatar
                      :if={person.cloak}
                      cloak={person.cloak}
                      actor={person}
                      class="size-6 text-[0.65rem]"
                    />
                    <.avatar
                      :if={!person.cloak}
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

            <.link
              :if={@scene && !@scenario && @can_manage_scene?}
              id="room-settings-link"
              navigate={~p"/rooms/#{@room}/settings"}
              class="flex items-center gap-1.5 rounded-lg px-2 py-1 text-sm opacity-70 transition hover:bg-base-200 hover:opacity-100"
            >
              <.icon name="hero-cog-6-tooth" class="size-4" /> Room settings
            </.link>
            <.link
              :if={!@scenario && @room != "lobby" && can_start_scenario?(assigns)}
              id="start-scene-link"
              navigate={~p"/scenarios?room=#{@room}"}
              class="flex items-center gap-1.5 rounded-lg px-2 py-1 text-sm text-violet-600 transition hover:bg-violet-500/10"
            >
              <.icon name="hero-sparkles" class="size-4" /> Start a scenario here
            </.link>
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
              <div :for={{id, message} <- @streams.messages} id={id}>
                <.scenario_intro
                  :if={message.kind == "scenario"}
                  message={message}
                  scenario={@scenarios[message.scenario_id]}
                />
                <div
                  :if={message.kind == "scenario_end"}
                  data-role="scenario-end"
                  class="my-4 flex items-center gap-3 text-xs opacity-70"
                >
                  <span class="h-px flex-1 bg-base-300"></span>
                  <span class="flex items-center gap-1.5 font-medium">
                    <.icon name="hero-flag" class="size-4" />
                    The scenario has ended · {message.username}
                  </span>
                  <span class="h-px flex-1 bg-base-300"></span>
                </div>
                <div
                  :if={message.kind == "chat"}
                  class="group flex gap-3 rounded-xl px-2 py-1.5 transition-colors hover:bg-base-200/60"
                >
                  <% author = author(message, @personas, @characters) %>
                  <button
                    type="button"
                    phx-click={author.profile? && "show_profile"}
                    phx-value-user-id={message.user_id}
                    phx-value-persona-id={message.persona_id}
                    phx-value-character-id={!author.actor && message.character_id}
                    phx-value-cloak-id={author.actor && message.character_id}
                    class={["h-fit shrink-0 rounded-full", author.profile? && "cursor-pointer"]}
                    aria-label={"Profile of #{author.name}"}
                  >
                    <.cloaked_avatar :if={author.actor} cloak={author} actor={author.actor} />
                    <.avatar
                      :if={!author.actor}
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
                        phx-value-character-id={!author.actor && message.character_id}
                        phx-value-cloak-id={author.actor && message.character_id}
                        class={["text-sm font-semibold", author.profile? && "hover:underline"]}
                      >
                        {author.name}
                      </button>

                      <span
                        :if={author.actor}
                        data-role="actor-badge"
                        title={"A human player in the role of #{author.name}"}
                        class="flex items-center gap-0.5 rounded bg-amber-500/15 px-1 text-[0.65rem] font-semibold text-amber-700 dark:text-amber-400"
                      >
                        <.icon name="hero-user" class="size-3" /> played by {author.actor.name}
                      </span>

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

          <div :if={@current_scope} class="relative">
            <div
              id="wardrobe"
              phx-click-away={JS.hide(to: "#wardrobe")}
              phx-window-keydown={JS.hide(to: "#wardrobe")}
              phx-key="Escape"
              class="absolute bottom-full left-3 z-30 mb-2 hidden w-72 rounded-2xl border border-base-300 bg-base-100 p-3 shadow-xl"
            >
              <h2 class="flex items-center gap-1.5 text-sm font-semibold">
                <.icon name="hero-identification" class="size-4 text-amber-600" /> Wardrobe
              </h2>
              <p class="mt-0.5 mb-2 text-xs opacity-60">
                Wear a character from the library in ##{@room}. Others see it's you playing.
              </p>
              <.form
                for={@wardrobe_form}
                id="wardrobe-search"
                phx-change="wardrobe_search"
                phx-submit="wardrobe_search"
              >
                <.input
                  field={@wardrobe_form[:query]}
                  type="search"
                  placeholder="Find a character…"
                  autocomplete="off"
                  phx-debounce="250"
                />
              </.form>
              <div class="max-h-60 space-y-0.5 overflow-y-auto">
                <button
                  :for={character <- @wardrobe_results}
                  id={"wardrobe-option-#{character.id}"}
                  type="button"
                  phx-click={JS.push("wear", value: %{id: character.id}) |> JS.hide(to: "#wardrobe")}
                  class="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-sm transition hover:bg-base-200"
                >
                  <.avatar
                    name={character.name}
                    avatar_id={character.avatar_id}
                    class="size-7 text-xs"
                  />
                  <span class="min-w-0 flex-1 truncate">{character.name}</span>
                </button>
              </div>
            </div>

            <div
              :if={@cloak}
              id="current-cloak"
              class="mx-3 mt-2 flex items-center gap-2 rounded-xl bg-amber-500/10 px-2 py-1 text-xs"
            >
              <.cloaked_avatar
                cloak={@cloak}
                actor={%{name: @me.name, avatar_id: @me[:avatar_id]}}
                class="size-6 text-[0.65rem]"
              />
              <span class="min-w-0 flex-1 truncate">
                You are playing <span class="font-semibold">{@cloak.name}</span>
              </span>
              <button
                id="take-off-cloak"
                type="button"
                phx-click="take_off_cloak"
                class="rounded-md px-1.5 py-0.5 font-medium opacity-70 transition hover:bg-amber-500/20 hover:opacity-100"
              >
                Take off
              </button>
            </div>
          </div>

          <.form
            :if={@current_scope}
            for={@form}
            id="message-form"
            phx-change="validate"
            phx-submit="send"
            class="flex gap-2 border-t border-base-300 px-3 pt-3"
          >
            <button
              id="wardrobe-toggle"
              type="button"
              phx-click={JS.toggle(to: "#wardrobe") |> JS.focus(to: "#wardrobe-search input")}
              class={[
                "grid size-10 shrink-0 place-items-center rounded-lg transition hover:bg-base-200",
                @cloak && "bg-amber-500/10"
              ]}
              aria-label="Wardrobe"
              title="Wardrobe: play a character"
            >
              <.avatar
                :if={@cloak}
                name={@cloak.name}
                avatar_id={@cloak.avatar_id}
                class="size-7 text-xs"
              />
              <.icon :if={!@cloak} name="hero-identification" class="size-5 opacity-70" />
            </button>
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

          <div :if={@profile.actor} class="space-y-5 text-left">
            <section id="profile-actor" class="flex gap-3">
              <.avatar
                name={@profile.actor.name}
                avatar_id={@profile.actor.avatar_id}
                class="size-14 text-xl"
              />
              <div class="min-w-0 flex-1">
                <p class="text-xs font-semibold tracking-wide uppercase opacity-60">Actor</p>
                <h2 class="text-lg font-semibold">{@profile.actor.name}</h2>
                <.markdown
                  :if={@profile.actor.description}
                  text={@profile.actor.description}
                  class="mt-1 text-sm opacity-80"
                />
              </div>
            </section>
            <section id="profile-role" class="flex gap-3 rounded-xl bg-amber-500/10 p-3">
              <.avatar name={@profile.name} avatar_id={@profile.avatar_id} class="size-14 text-xl" />
              <div class="min-w-0 flex-1">
                <p class="text-xs font-semibold tracking-wide text-amber-700 uppercase dark:text-amber-400">
                  Acting as
                </p>
                <h2 class="text-lg font-semibold">{@profile.name}</h2>
                <.markdown
                  :if={@profile.description}
                  text={@profile.description}
                  class="mt-1 max-h-60 overflow-y-auto text-sm opacity-80"
                />
              </div>
            </section>
          </div>

          <div :if={!@profile.actor}>
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
      </div>
    </Layouts.app>
    """
  end

  attr :cloak, :map, required: true, doc: "the worn character's name and avatar_id"
  attr :actor, :map, required: true, doc: "the player's name and avatar_id"
  attr :class, :any, default: "size-9 text-sm"

  # The cloak in front, the player's own avatar peeking out behind it.
  defp cloaked_avatar(assigns) do
    ~H"""
    <span class="flex -space-x-2">
      <.avatar
        name={@cloak.name}
        avatar_id={@cloak.avatar_id}
        class={["relative z-[1] ring-2 ring-amber-400/70", @class]}
        data-role="cloak-avatar"
      />
      <.avatar
        name={@actor.name}
        avatar_id={@actor.avatar_id}
        class={["opacity-90", @class]}
        data-role="actor-avatar"
      />
    </span>
    """
  end

  attr :message, :map, required: true
  attr :scenario, :map, default: nil, doc: "nil once the scenario was deleted"

  defp scenario_intro(assigns) do
    ~H"""
    <div
      data-role="scenario-intro"
      data-scenario-id={@message.scenario_id}
      class="my-4 overflow-hidden rounded-2xl border border-violet-500/30 bg-base-100/80 shadow-sm backdrop-blur-sm"
    >
      <img
        :if={@scenario && @scenario.card_image_id}
        src={~p"/avatars/#{@scenario.card_image_id}"}
        alt=""
        class="aspect-[16/5] w-full object-cover"
      />
      <div class="space-y-2 bg-gradient-to-br from-violet-500/10 to-fuchsia-500/10 p-4">
        <p class="flex items-center gap-1.5 text-xs font-semibold tracking-wide text-violet-600 uppercase">
          <.icon name="hero-sparkles" class="size-4" /> This channel changes the scenario to:
        </p>
        <h3 class="text-xl font-bold tracking-tight">
          {if @scenario, do: @scenario.title, else: @message.body}
        </h3>
        <p :if={@scenario && @scenario.topic} class="text-sm italic opacity-75">
          {@scenario.topic}
        </p>
        <.markdown
          :if={@scenario && @scenario.description}
          text={@scenario.description}
          class="max-h-72 overflow-y-auto text-sm leading-relaxed"
        />
        <p class="text-xs opacity-50">
          Started by {@message.username} ·
          <time
            id={"message-time-#{@message.id}"}
            datetime={DateTime.to_iso8601(@message.inserted_at)}
            title={Calendar.strftime(@message.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
            phx-hook=".LocalTime"
            phx-update="ignore"
          >
            {Calendar.strftime(@message.inserted_at, "%H:%M")}
          </time>
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Chat.subscribe_rooms()
      Presence.subscribe_rooms()
      Assistant.subscribe()
      Scenarios.subscribe()
    end

    {:ok,
     socket
     |> assign(:room, nil)
     |> assign(:roleplay_rooms, Rooms.roleplay_room_names())
     |> assign(
       scene: nil,
       scenario: nil,
       cast: [],
       can_manage_scene?: false,
       show_scenario?: false
     )
     |> assign(:scenarios, %{})
     |> assign(cloak: nil, wardrobe_results: [])
     |> assign(:wardrobe_form, to_form(%{"query" => ""}, as: :wardrobe))
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
    cloak = Rooms.get_cloak(socket.assigns.current_scope, room)
    me = socket.assigns.me |> Map.put(:typing, false) |> put_cloak_meta(cloak)

    if connected?(socket) do
      Chat.subscribe(room)
      Rooms.subscribe(room)
      Presence.subscribe(room)
      {:ok, _} = Presence.track_user(room, socket.id, me)
      {:ok, _} = Presence.put_room(socket.id, room)
    end

    socket
    |> assign(:room, room)
    |> assign(:cloak, cloak)
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
    |> remember_scenarios(messages)
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

    case Rooms.post_message(scope, room, params) do
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
     |> remember_scenarios(older)
     |> assign(oldest_message: List.first(older) || oldest, more_messages?: more?)
     # Inserting newest-first at index 0 leaves them in chronological order.
     |> stream(:messages, Enum.reverse(older), at: 0)}
  end

  def handle_event("show_profile", %{"user-id" => user_id, "cloak-id" => cloak_id}, socket)
      when user_id != "" and cloak_id != "" do
    {:noreply, assign(socket, :profile, cloaked_profile(user_id, cloak_id))}
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

  def handle_event("wardrobe_search", %{"wardrobe" => %{"query" => query}}, socket) do
    {:noreply,
     socket
     |> assign(:wardrobe_form, to_form(%{"query" => query}, as: :wardrobe))
     |> assign(:wardrobe_results, Characters.search_characters(query, [], 8))}
  end

  def handle_event("wear", %{"id" => id}, socket) do
    %{current_scope: scope, room: room} = socket.assigns

    case Rooms.wear_character(scope, room, id) do
      {:ok, character} ->
        {:noreply, put_cloak(socket, character)}

      {:error, :taken} ->
        {:noreply, put_flash(socket, :error, "Someone here is already wearing that character.")}

      {:error, :cast} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "The AI plays this character here, and the game masters keep it that way."
         )}

      {:error, _not_found_or_guest} ->
        {:noreply, put_flash(socket, :error, "That character can't be worn.")}
    end
  end

  def handle_event("take_off_cloak", _params, socket) do
    %{current_scope: scope, room: room} = socket.assigns

    case Rooms.take_off_cloak(scope, room) do
      :ok -> {:noreply, put_cloak(socket, nil)}
      {:error, :unauthorized} -> {:noreply, socket}
    end
  end

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
     |> remember_scenarios([message])
     |> assign(:has_messages?, true)
     |> stream_insert(:messages, message)}
  end

  # Still in flight from a room we just left.
  def handle_info({:new_message, _message}, socket), do: {:noreply, socket}

  def handle_info({:room_updated, %{name: room} = scene}, %{assigns: %{room: room}} = socket) do
    roleplay_rooms =
      if scene.scenario_id,
        do: MapSet.put(socket.assigns.roleplay_rooms, room),
        else: MapSet.delete(socket.assigns.roleplay_rooms, room)

    {:noreply, socket |> assign(:roleplay_rooms, roleplay_rooms) |> assign_scene(scene)}
  end

  def handle_info({:room_updated, _scene}, socket), do: {:noreply, socket}

  # Others' cloaks show through presence. Ours may have changed elsewhere
  # (another tab): show it and pass it on to presence.
  def handle_info({:cloak_changed, user_id}, socket) do
    case socket.assigns.current_scope do
      %{user: %{id: ^user_id}} = scope ->
        {:noreply, put_cloak(socket, Rooms.get_cloak(scope, socket.assigns.room))}

      _someone_else ->
        {:noreply, socket}
    end
  end

  # Edits of the scenario this room plays show up in the scene header.
  def handle_info({:scenario_updated, scenario}, socket) do
    socket =
      if Map.has_key?(socket.assigns.scenarios, scenario.id),
        do: update(socket, :scenarios, &Map.put(&1, scenario.id, scenario)),
        else: socket

    case socket.assigns.scene do
      %{scenario_id: id} = scene when id == scenario.id ->
        {:noreply, assign_scene(socket, %{scene | scenario: scenario})}

      _other ->
        {:noreply, socket}
    end
  end

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

  defp put_cloak(socket, cloak) do
    me = put_cloak_meta(socket.assigns.me, cloak)
    if connected?(socket), do: Presence.update_user(socket.assigns.room, socket.id, me)

    socket
    |> assign(:cloak, cloak)
    |> assign(:me, me)
  end

  # Guests can't wear cloaks.
  defp put_cloak_meta(%{name: nil} = me, _cloak), do: me

  defp put_cloak_meta(me, nil),
    do: Map.merge(me, %{cloak_id: nil, cloak_name: nil, cloak_avatar_id: nil})

  defp put_cloak_meta(me, cloak),
    do:
      Map.merge(me, %{
        cloak_id: cloak.id,
        cloak_name: cloak.name,
        cloak_avatar_id: cloak.avatar_id
      })

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
          assistant: meta[:assistant] == true,
          cloak:
            meta[:cloak_id] &&
              %{id: meta.cloak_id, name: meta.cloak_name, avatar_id: meta.cloak_avatar_id}
        }
      end

    typing_names =
      for {key, %{typing: true} = meta} <- users, key != socket.id, uniq: true do
        meta[:cloak_name] || meta.name || "Someone"
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
          assistant: false,
          actor: nil
        }
    end
  end

  # A player in a cloak: both the player and the character they play.
  defp cloaked_profile(user_id, character_id) do
    with %{} = actor <- user_profile(user_id),
         %{} = role <- character_profile(character_id) do
      %{role | actor: actor}
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
          assistant: false,
          actor: nil
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
          assistant: true,
          actor: nil
        }
    end
  end

  # The scene of a role-play room; nil for plain chat rooms.
  defp assign_scene(socket, scene) do
    socket
    |> assign(:scene, scene)
    |> assign(:scenario, scene && scene.scenario)
    |> assign(:cast, if(scene, do: Rooms.list_cast(scene), else: []))
    |> assign(
      :can_manage_scene?,
      scene != nil and Rooms.can_manage?(socket.assigns.current_scope, scene)
    )
  end

  # A room's game masters start its scenarios; admins also those of rooms
  # nobody runs.
  defp can_start_scenario?(%{scene: nil, current_scope: scope}), do: Accounts.admin?(scope)
  defp can_start_scenario?(%{can_manage_scene?: can_manage?}), do: can_manage?

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

  # Loads the scenarios that intro messages in `messages` announce.
  defp remember_scenarios(socket, messages) do
    known = socket.assigns.scenarios

    missing =
      for %{kind: "scenario", scenario_id: id} <- messages,
          is_integer(id),
          not Map.has_key?(known, id),
          uniq: true do
        id
      end

    case missing do
      [] ->
        socket

      ids ->
        loaded = Map.new(Scenarios.list_scenarios_by_ids(ids), &{&1.id, &1})
        assign(socket, :scenarios, Map.merge(known, loaded))
    end
  end

  # Who wrote a message, as shown now: people by their current profile,
  # personas by their current avatar, characters by their current sheet.
  # Legacy messages and deleted characters have no profile.
  # A player in a cloak: the character, played by the player (`actor`).
  defp author(
         %{from_assistant: false, character_id: id, user: %{} = user} = message,
         personas,
         characters
       )
       when is_integer(id) do
    case characters[id] do
      nil ->
        author(%{message | character_id: nil}, personas, characters)

      character ->
        %{
          name: character.name,
          avatar_id: character.avatar_id,
          profile?: true,
          actor: %{name: message.username, avatar_id: user.avatar_id}
        }
    end
  end

  defp author(%{character_id: id} = message, _personas, characters) when is_integer(id) do
    case characters[id] do
      nil ->
        %{name: message.username, avatar_id: nil, profile?: false, actor: nil}

      character ->
        %{name: character.name, avatar_id: character.avatar_id, profile?: true, actor: nil}
    end
  end

  defp author(%{persona_id: id} = message, personas, _characters) when is_integer(id) do
    persona = personas[id]

    %{
      name: message.username,
      avatar_id: persona && persona.avatar_id,
      profile?: persona != nil,
      actor: nil
    }
  end

  defp author(%{user: %{avatar_id: avatar_id}} = message, _personas, _characters) do
    %{name: message.username, avatar_id: avatar_id, profile?: true, actor: nil}
  end

  defp author(message, _personas, _characters),
    do: %{name: message.username, avatar_id: nil, profile?: false, actor: nil}

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
