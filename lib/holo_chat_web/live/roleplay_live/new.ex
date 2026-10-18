defmodule HoloChatWeb.RoleplayLive.New do
  use HoloChatWeb, :live_view

  alias HoloChat.Rooms

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-lg overflow-y-auto py-8">
        <.header>
          New scene
          <:subtitle>
            You become its game master. You can add images and more game masters afterwards.
          </:subtitle>
        </.header>

        <.form for={@form} id="room-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:title]} type="text" label="Title" placeholder="The Sunken Keep" />
          <.input
            field={@form[:name]}
            type="text"
            label="Room name"
            placeholder="sunken-keep"
            autocomplete="off"
          />
          <p class="-mt-1 mb-3 text-xs opacity-60">
            Lowercase letters, digits and dashes. The room lives at /rooms/<i>name</i>.
          </p>
          <.input
            field={@form[:topic]}
            type="text"
            label="Topic"
            placeholder="One line shown on the card and above the chat"
          />
          <.input
            field={@form[:scenario]}
            type="textarea"
            label="Scenario"
            rows="6"
            placeholder="Where and when the scene plays, and what is going on."
          />
          <.button variant="primary" phx-disable-with="Creating…">Create scene</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "New scene")
     |> assign(:form, to_form(Rooms.change_room(nil), as: :room))}
  end

  @impl true
  def handle_event("validate", %{"room" => params}, socket) do
    changeset = Rooms.change_room(nil, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :room))}
  end

  def handle_event("save", %{"room" => params}, socket) do
    case Rooms.create_roleplay_room(socket.assigns.current_scope, params) do
      {:ok, room} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scene created. Welcome, game master!")
         |> push_navigate(to: ~p"/rooms/#{room.name}")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :room))}
    end
  end
end
