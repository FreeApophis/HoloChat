defmodule HoloChatWeb.ChatLive do
  use HoloChatWeb, :live_view

  alias HoloChat.Chat
  alias HoloChat.Chat.Message

  @default_room "lobby"

  # Literal class strings so Tailwind picks them up.
  @avatar_colors ~w(
    bg-rose-500 bg-orange-500 bg-amber-500 bg-lime-600 bg-emerald-600
    bg-teal-600 bg-sky-600 bg-indigo-500 bg-violet-500 bg-fuchsia-600
  )

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex min-h-0 flex-1 flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm">
        <div class="flex flex-wrap items-center justify-between gap-3 border-b border-base-300 px-4 py-3">
          <h1 id="room-title" class="flex items-center gap-1 text-base font-semibold">
            <.icon name="hero-hashtag" class="size-4 opacity-60" />
            {@room}
          </h1>
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
                  datetime={DateTime.to_iso8601(message.inserted_at)}
                  title={Calendar.strftime(message.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
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

        <.form
          for={@form}
          id="message-form"
          phx-change="validate"
          phx-submit="send"
          class="flex flex-col gap-2 border-t border-base-300 p-3 sm:flex-row sm:items-start"
        >
          <div class="sm:w-40">
            <.input
              field={@form[:username]}
              type="text"
              placeholder="Your name"
              autocomplete="nickname"
            />
          </div>
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
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    room = Map.get(params, "room", @default_room)

    if Chat.valid_room?(room) do
      if connected?(socket), do: Chat.subscribe(room)

      {:ok,
       socket
       |> assign(:room, room)
       |> assign(:page_title, "#" <> room)
       |> assign(:room_form, to_form(%{"name" => ""}, as: :room))
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

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("send", %{"message" => params}, socket) do
    case Chat.create_message(socket.assigns.room, params) do
      {:ok, message} ->
        # The message itself arrives via PubSub; keep the name, clear the body.
        {:noreply, assign_message_form(socket, %{"username" => message.username})}

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
