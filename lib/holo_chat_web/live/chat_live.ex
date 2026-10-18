defmodule HoloChatWeb.ChatLive do
  use HoloChatWeb, :live_view

  alias HoloChat.Chat
  alias HoloChat.Chat.Message
  alias HoloChatWeb.Presence

  @default_room "lobby"
  @typing_timeout :timer.seconds(3)
  @max_avatars 5

  # Literal class strings so Tailwind picks them up.
  @avatar_colors ~w(
    bg-rose-500 bg-orange-500 bg-amber-500 bg-lime-600 bg-emerald-600
    bg-teal-600 bg-sky-600 bg-indigo-500 bg-violet-500 bg-fuchsia-600
  )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm">
        <div class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-3">
          <div class="flex items-center gap-3">
            <h1 id="room-title" class="flex items-center gap-1 text-base font-semibold">
              <.icon name="hero-hashtag" class="size-4 opacity-60" />
              {@room}
            </h1>
            <div
              id="online-users"
              class="flex items-center gap-2"
              title={online_summary(@online_names, @guest_count)}
            >
              <div class="flex -space-x-1.5">
                <div
                  :for={name <- Enum.take(@online_names, @max_avatars)}
                  class={[
                    "grid size-6 place-items-center rounded-full text-[0.65rem] font-semibold text-white ring-2 ring-base-100",
                    avatar_color(name)
                  ]}
                >
                  {initial(name)}
                </div>
              </div>
              <span id="online-count" class="flex items-center gap-1.5 text-xs opacity-70">
                <span class="size-2 animate-pulse rounded-full bg-emerald-500"></span>
                {length(@online_names) + @guest_count} online
              </span>
            </div>
          </div>
          <.form
            for={@room_form}
            id="room-form"
            phx-submit="switch_room"
            class="flex items-center gap-2"
          >
            <input
              type="text"
              name={@room_form[:name].name}
              value={@room_form[:name].value}
              placeholder="Join a room…"
              aria-label="Room name"
              autocomplete="off"
              class="w-40 rounded-lg border border-base-300 bg-base-200 px-3 py-1.5 text-sm outline-none transition focus:border-primary focus:ring-2 focus:ring-primary/30"
            />
            <button
              type="submit"
              class="rounded-lg px-2 py-1.5 text-sm transition hover:bg-base-200"
              aria-label="Join room"
            >
              <.icon name="hero-arrow-right" class="size-4" />
            </button>
          </.form>
        </div>

        <div
          id="messages"
          phx-update="stream"
          phx-hook=".ScrollToBottom"
          class="min-h-0 flex-1 space-y-1 overflow-y-auto px-4 py-4"
        >
          <div
            id="messages-empty"
            class="hidden h-full flex-col items-center justify-center gap-2 text-center opacity-60 only:flex"
          >
            <.icon name="hero-sparkles" class="size-8" />
            <p class="text-sm">No messages in #{@room} yet. Say hi!</p>
          </div>
          <div
            :for={{id, message} <- @streams.messages}
            id={id}
            class="group flex gap-3 rounded-xl px-2 py-1.5 transition-colors hover:bg-base-200/60"
          >
            <div class={[
              "grid size-9 shrink-0 place-items-center rounded-full text-sm font-semibold text-white",
              avatar_color(message.username)
            ]}>
              {initial(message.username)}
            </div>
            <div class="min-w-0">
              <div class="flex items-baseline gap-2">
                <span class="text-sm font-semibold">{message.username}</span>
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
              <p class="whitespace-pre-wrap break-words text-sm leading-relaxed">{message.body}</p>
            </div>
          </div>
        </div>
        <script :type={Phoenix.LiveView.ColocatedHook} name=".ScrollToBottom">
          export default {
            mounted() {
              this.scroll()
              this.observer = new MutationObserver(() => {
                // Only follow new messages if the user hasn't scrolled up to read history.
                if (this.nearBottom) this.scroll()
              })
              this.el.addEventListener("scroll", () => this.trackPosition())
              this.observer.observe(this.el, {childList: true})
              this.trackPosition()
            },
            destroyed() { this.observer.disconnect() },
            trackPosition() {
              const el = this.el
              this.nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80
            },
            scroll() { this.el.scrollTop = this.el.scrollHeight; this.nearBottom = true }
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
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    room = Map.get(params, "room", @default_room)

    if Chat.valid_room?(room) do
      me = %{name: username(socket.assigns.current_scope), typing: false}

      if connected?(socket) do
        Chat.subscribe(room)
        Presence.subscribe(room)
        {:ok, _} = Presence.track_user(room, socket.id, me)
      end

      {:ok,
       socket
       |> assign(:room, room)
       |> assign(:page_title, "#" <> room)
       |> assign(:room_form, to_form(%{"name" => ""}, as: :room))
       |> assign(:max_avatars, @max_avatars)
       |> assign(:me, me)
       |> assign(:typing_timer, nil)
       |> assign_presence()
       |> assign_message_form(%{})
       |> stream(:messages, Chat.list_recent_messages(room))}
    else
      {:ok,
       socket
       |> put_flash(:error, "Room names may only contain lowercase letters, digits and dashes.")
       |> push_navigate(to: ~p"/")}
    end
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

  def handle_event("switch_room", %{"room" => %{"name" => name}}, socket) do
    room = normalize_room(name)

    if Chat.valid_room?(room) do
      {:noreply, push_navigate(socket, to: room_path(room))}
    else
      {:noreply, put_flash(socket, :error, "Please enter a room name.")}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    {:noreply, stream_insert(socket, :messages, message)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign_presence(socket)}
  end

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

    typing_names =
      for {key, %{typing: true} = meta} <- users, key != socket.id, uniq: true do
        meta.name || "Someone"
      end

    socket
    |> assign(:online_names, names |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort())
    |> assign(:guest_count, Enum.count(names, &is_nil/1))
    |> assign(:typing_names, Enum.sort(typing_names))
  end

  defp username(%{user: %{username: username}}), do: username
  defp username(_guest), do: nil

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

  defp room_path(@default_room), do: ~p"/"
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

  defp initial(username) do
    username |> String.first() |> String.upcase()
  end

  defp avatar_color(username) do
    Enum.at(@avatar_colors, :erlang.phash2(username, length(@avatar_colors)))
  end
end
