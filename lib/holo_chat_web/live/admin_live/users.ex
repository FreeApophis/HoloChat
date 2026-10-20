defmodule HoloChatWeb.AdminLive.Users do
  use HoloChatWeb, :live_view

  alias HoloChat.{Accounts, Rooms}

  @roles [
    {:admin, :is_admin, "Admin", "Grants roles and configures the assistant"},
    {:moderator, :is_moderator, "Moderator", "Manages every room"},
    {:library_editor, :is_library_editor, "Library editor", "Edits every scenario and character"},
    {:news_editor, :is_news_editor, "News editor", "Writes and publishes the news"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-3xl space-y-6 overflow-y-auto py-6">
        <.header>
          Users and roles
          <:subtitle>
            Give people site-wide roles, or make them game master of a room.
          </:subtitle>
          <:actions>
            <.link
              id="admin-assistant-link"
              navigate={~p"/admin/assistant"}
              class="flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm font-medium opacity-70 transition hover:bg-base-200 hover:opacity-100"
            >
              <.icon name="hero-cpu-chip" class="size-4" /> AI assistant
            </.link>
          </:actions>
        </.header>

        <.form for={@search_form} id="user-search-form" phx-change="search" phx-submit="search">
          <.input
            field={@search_form[:query]}
            type="search"
            placeholder="Search by username"
            autocomplete="off"
            phx-debounce="200"
          />
        </.form>

        <p :if={@users == []} id="no-users" class="text-sm opacity-60">No users found.</p>

        <ul id="users" class="space-y-3">
          <li
            :for={user <- @users}
            id={"user-#{user.id}"}
            class="rounded-xl border border-base-300 bg-base-100 p-4 shadow-sm"
          >
            <div class="flex flex-wrap items-center gap-3">
              <.avatar name={user.username} avatar_id={user.avatar_id} class="size-9 text-sm" />
              <span class="min-w-0 flex-1 truncate font-semibold">{user.username}</span>
              <div class="flex flex-wrap gap-1.5">
                <button
                  :for={{role, field, label, hint} <- roles()}
                  id={"role-#{user.id}-#{role}"}
                  type="button"
                  phx-click="toggle_role"
                  phx-value-id={user.id}
                  phx-value-role={role}
                  data-granted={to_string(Map.fetch!(user, field))}
                  aria-pressed={to_string(Map.fetch!(user, field))}
                  disabled={role == :admin && user.id == @current_scope.user.id}
                  title={hint}
                  class={[
                    "rounded-full border px-2.5 py-1 text-xs font-medium transition disabled:cursor-not-allowed disabled:opacity-60",
                    if(Map.fetch!(user, field),
                      do: "border-primary bg-primary text-primary-content hover:opacity-90",
                      else: "border-base-300 opacity-70 hover:border-primary hover:opacity-100"
                    )
                  ]}
                >
                  {label}
                </button>
              </div>
            </div>

            <div class="mt-3 flex flex-wrap items-start gap-2 border-t border-base-300 pt-3">
              <span class="pt-1.5 text-xs font-medium opacity-60">Game master of</span>
              <span
                :for={room <- Map.get(@mastered, user.id, [])}
                id={"mastered-#{user.id}-#{room}"}
                class="flex items-center gap-1 rounded-full bg-violet-500/10 py-1 pr-1 pl-2.5 text-xs font-medium text-violet-700 dark:text-violet-300"
              >
                #{room}
                <button
                  id={"dismiss-#{user.id}-#{room}"}
                  type="button"
                  phx-click="dismiss"
                  phx-value-id={user.id}
                  phx-value-room={room}
                  aria-label={"Dismiss as game master of ##{room}"}
                  class="rounded-full p-0.5 transition hover:bg-violet-500/20"
                >
                  <.icon name="hero-x-mark" class="size-3" />
                </button>
              </span>
              <.form
                for={Map.get(@appoint_forms, user.id, @blank_appoint_form)}
                id={"appoint-form-#{user.id}"}
                phx-submit="appoint"
                class="flex flex-1 items-start gap-1.5"
              >
                <input type="hidden" name="appoint[id]" value={user.id} />
                <div class="min-w-32 flex-1">
                  <.input
                    field={Map.get(@appoint_forms, user.id, @blank_appoint_form)[:room]}
                    id={"appoint-room-#{user.id}"}
                    type="text"
                    placeholder="room-name"
                    autocomplete="off"
                    aria-label={"Room to make #{user.username} game master of"}
                  />
                </div>
                <.button>Appoint</.button>
              </.form>
            </div>
          </li>
        </ul>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Users and roles")
     |> assign(:blank_appoint_form, to_form(%{"room" => ""}, as: :appoint))
     |> assign(:appoint_forms, %{})
     |> search("")}
  end

  @impl true
  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    {:noreply, search(socket, query)}
  end

  def handle_event("toggle_role", %{"id" => id, "role" => role}, socket) do
    scope = socket.assigns.current_scope
    {role, field, _label, _hint} = Enum.find(roles(), fn {r, _, _, _} -> to_string(r) == role end)
    user = Enum.find(socket.assigns.users, &(to_string(&1.id) == id))

    case Accounts.set_role(scope, id, role, not Map.fetch!(user, field)) do
      {:ok, _user} ->
        {:noreply, refresh(socket)}

      {:error, :own_admin} ->
        {:noreply, put_flash(socket, :error, "You can't revoke your own admin rights.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not change that role.")}
    end
  end

  def handle_event("appoint", %{"appoint" => %{"id" => id, "room" => room}}, socket) do
    scope = socket.assigns.current_scope
    room = String.trim(room)

    case Rooms.appoint_game_master(scope, room, id) do
      {:ok, _room} ->
        {:noreply,
         socket
         |> update(:appoint_forms, &Map.delete(&1, String.to_integer(id)))
         |> refresh()}

      {:error, reason} ->
        form = to_form(%{"room" => room}, as: :appoint, errors: [room: {refusal(reason), []}])
        {:noreply, update(socket, :appoint_forms, &Map.put(&1, String.to_integer(id), form))}
    end
  end

  def handle_event("dismiss", %{"id" => id, "room" => name}, socket) do
    with %{} = room <- Rooms.get_room(name),
         :ok <-
           Rooms.remove_game_master(socket.assigns.current_scope, room, String.to_integer(id)) do
      {:noreply, refresh(socket)}
    else
      _error -> {:noreply, put_flash(socket, :error, "Could not dismiss that game master.")}
    end
  end

  defp roles, do: @roles

  defp search(socket, query) do
    {:ok, users} = Accounts.search_users(socket.assigns.current_scope, query)

    socket
    |> assign(:search_form, to_form(%{"query" => query}, as: :search))
    |> assign(:users, users)
    |> assign(:mastered, Map.new(users, &{&1.id, Rooms.list_mastered_rooms(&1.id)}))
  end

  defp refresh(socket), do: search(socket, socket.assigns.search_form[:query].value)

  defp refusal(:not_found), do: "No room with that name, or the user is gone"
  defp refusal(:lobby), do: "The lobby has no game masters"
  defp refusal(:unauthorized), do: "Only admins and moderators can appoint game masters"
end
