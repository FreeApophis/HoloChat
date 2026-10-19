defmodule HoloChatWeb.RoleplayLive.New do
  use HoloChatWeb, :live_view

  alias HoloChat.{Rooms, Scenarios}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-lg overflow-y-auto py-8">
        <.header>
          New scene
          <:subtitle>
            Set up a scene for a scenario. You become its game master: pick its cast and
            settings, then start it in a channel when you are ready.
          </:subtitle>
        </.header>

        <div
          :if={@scenario_options == []}
          id="no-scenarios"
          class="rounded-2xl border border-dashed border-base-300 p-6 text-center text-sm"
        >
          <p class="opacity-70">There are no scenarios to play yet.</p>
          <.link
            navigate={~p"/scenarios/new"}
            class="mt-2 inline-block font-medium text-primary hover:underline"
          >
            Write the first one
          </.link>
        </div>

        <.form
          :if={@scenario_options != []}
          for={@form}
          id="room-form"
          phx-change="validate"
          phx-submit="save"
        >
          <.input
            field={@form[:scenario_id]}
            type="select"
            label="Scenario"
            prompt="Pick a scenario"
            options={@scenario_options}
          />
          <p class="-mt-1 mb-3 text-xs opacity-60">
            Missing one? <.link
              navigate={~p"/scenarios/new"}
              class="font-medium text-primary hover:underline"
            >Write a scenario</.link>.
          </p>
          <%!-- An admin coming from a chat room starts the scene there. --%>
          <div :if={@channel} id="scene-channel" class="mb-3 text-sm opacity-70">
            <input type="hidden" name={@form[:name].name} value={@channel} />
            Plays in <span class="font-medium">#{@channel}</span>.
            <p
              :for={msg <- Enum.map(@form[:name].errors, &translate_error/1)}
              class="mt-1.5 flex items-center gap-2 text-sm text-error"
            >
              <.icon name="hero-exclamation-circle" class="size-5" />
              {msg}
            </p>
          </div>
          <.button variant="primary" phx-disable-with="Creating…">Create the scene</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    # Coming from a scenario card preselects that scenario; an admin coming
    # from a chat room fills in its name.
    attrs = %{"scenario_id" => params["scenario"], "name" => params["room"]}

    {:ok,
     socket
     |> assign(:page_title, "New scene")
     |> assign(:channel, params["room"])
     |> assign(:scenario_options, Enum.map(Scenarios.list_scenarios(), &{&1.title, &1.id}))
     |> assign(:form, to_form(Rooms.change_room(nil, attrs), as: :room))}
  end

  @impl true
  def handle_event("validate", %{"room" => params}, socket) do
    changeset = Rooms.change_room(nil, params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :form, to_form(changeset, as: :room))}
  end

  def handle_event("save", %{"room" => params}, socket) do
    case Rooms.create_roleplay_room(socket.assigns.current_scope, params) do
      {:ok, %{name: nil} = scene} ->
        {:noreply,
         socket
         |> put_flash(:info, "Scene created. Cast it, then start it in a channel.")
         |> push_navigate(to: ~p"/scenes/#{scene.id}/settings")}

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
