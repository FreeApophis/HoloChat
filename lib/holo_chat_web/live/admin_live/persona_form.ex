defmodule HoloChatWeb.AdminLive.PersonaForm do
  use HoloChatWeb, :live_view

  alias HoloChat.Assistant
  alias HoloChat.Assistant.Persona

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-xl space-y-6 overflow-y-auto py-6">
        <.header>
          {@page_title}
          <:subtitle>
            <.link navigate={~p"/admin/assistant"} class="text-primary hover:underline">
              ← Back to the AI assistant
            </.link>
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="persona-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-1"
        >
          <.input field={@form[:name]} type="text" label="Name (answers to @Name)" />
          <.input
            field={@form[:rooms]}
            value={rooms_text(@form[:rooms].value)}
            type="text"
            label="Rooms (comma-separated)"
            placeholder="lobby, help"
          />
          <.input
            field={@form[:system_prompt]}
            type="textarea"
            label="System prompt ({name} is replaced with the persona's name)"
            rows="8"
          />
          <div class="grid gap-x-4 sm:grid-cols-3">
            <.input
              field={@form[:context_messages]}
              type="number"
              label="Context messages"
              min="1"
              max="50"
            />
            <.input field={@form[:max_tokens]} type="number" label="Max tokens" min="16" max="4096" />
            <.input
              field={@form[:temperature]}
              type="number"
              label="Temperature"
              min="0"
              max="2"
              step="0.1"
            />
          </div>

          <.button variant="primary" phx-disable-with="Saving…">Save persona</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    persona =
      case socket.assigns.live_action do
        :new -> %Persona{}
        :edit -> Assistant.get_persona!(params["id"])
      end

    {:ok,
     socket
     |> assign(:persona, persona)
     |> assign(:page_title, page_title(socket.assigns.live_action, persona))
     |> assign_form(Assistant.change_persona(persona))}
  end

  @impl true
  def handle_event("validate", %{"persona" => params}, socket) do
    changeset =
      socket.assigns.persona
      |> Assistant.change_persona(parse_rooms(params))
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"persona" => params}, socket) do
    case save(socket, parse_rooms(params)) do
      {:ok, _persona} ->
        {:noreply,
         socket
         |> put_flash(:info, "Persona saved.")
         |> push_navigate(to: ~p"/admin/assistant")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(%{assigns: %{live_action: :new}} = socket, params) do
    Assistant.create_persona(socket.assigns.current_scope, params)
  end

  defp save(%{assigns: %{live_action: :edit}} = socket, params) do
    Assistant.update_persona(socket.assigns.current_scope, socket.assigns.persona, params)
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :persona))

  # The form edits rooms as "lobby, #help"; the context takes a list.
  defp parse_rooms(%{"rooms" => rooms} = params) when is_binary(rooms) do
    list =
      rooms |> String.split(",") |> Enum.map(&(&1 |> String.trim() |> String.trim_leading("#")))

    Map.put(params, "rooms", list)
  end

  defp parse_rooms(params), do: params

  defp rooms_text(rooms) when is_list(rooms), do: Enum.join(rooms, ", ")
  defp rooms_text(rooms), do: rooms

  defp page_title(:new, _persona), do: "New persona"
  defp page_title(:edit, persona), do: "Edit @#{persona.name}"
end
