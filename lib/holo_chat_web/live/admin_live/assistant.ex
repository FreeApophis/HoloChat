defmodule HoloChatWeb.AdminLive.Assistant do
  use HoloChatWeb, :live_view

  alias HoloChat.Assistant

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-xl space-y-8 overflow-y-auto py-6">
        <.header>
          AI assistant
          <:subtitle>
            Personas answer messages that mention them as @Name in their rooms.
            They need an OpenAI-compatible server such as koboldcpp.
          </:subtitle>
          <:actions>
            <.link
              id="admin-users-link"
              navigate={~p"/admin/users"}
              class="flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm font-medium opacity-70 transition hover:bg-base-200 hover:opacity-100"
            >
              <.icon name="hero-users" class="size-4" /> Users and roles
            </.link>
          </:actions>
        </.header>

        <section>
          <h2 class="mb-2 text-sm font-semibold">Connection</h2>
          <.form
            for={@form}
            id="assistant-settings-form"
            phx-change="validate"
            phx-submit="save"
            class="space-y-1"
          >
            <.input field={@form[:enabled]} type="checkbox" label="Enabled" />

            <div class="flex items-end gap-2">
              <div class="flex-1">
                <.input
                  field={@form[:endpoint_url]}
                  type="text"
                  label="Endpoint URL"
                  placeholder="http://localhost:5001"
                />
              </div>
              <button
                type="button"
                id="test-connection"
                phx-click="test_connection"
                phx-disable-with="Testing…"
                class="btn btn-soft mb-2"
              >
                Test connection
              </button>
            </div>
            <div id="connection-status" class="-mt-1 mb-3 min-h-5 text-sm">
              <%= case @connection do %>
                <% {:ok, info} -> %>
                  <p class="text-success">
                    <.icon name="hero-check-circle" class="size-4" /> Connected, serving {info.model}
                  </p>
                  <dl class="mt-1 grid grid-cols-[auto_1fr] gap-x-3 text-xs opacity-80">
                    <%= if info.server do %>
                      <dt>Server</dt>
                      <dd id="connection-server">{info.server}</dd>
                    <% end %>
                    <%= if info.context_length do %>
                      <dt>Context window</dt>
                      <dd id="connection-context">{delimit(info.context_length)} tokens</dd>
                    <% end %>
                    <%= if info.generation_speed do %>
                      <dt>Last generation</dt>
                      <dd id="connection-speed">{format_speed(info.generation_speed)} tokens/s</dd>
                    <% end %>
                  </dl>
                  <p
                    :if={too_large = oversized_personas(@personas, info.context_length)}
                    id="context-warning"
                    class="mt-2 text-warning"
                  >
                    <.icon name="hero-exclamation-triangle" class="size-4" />
                    In a busy room, the context of {Enum.join(too_large, ", ")} can exceed this
                    model's context window. Lower their context messages or max tokens.
                  </p>
                <% {:error, reason} -> %>
                  <p class="text-error">
                    <.icon name="hero-x-circle" class="size-4" /> Could not connect: {reason}
                  </p>
                <% nil -> %>
              <% end %>
            </div>

            <.button variant="primary" phx-disable-with="Saving…">Save connection</.button>
          </.form>
        </section>

        <section id="personas">
          <div class="mb-2 flex items-center justify-between">
            <h2 class="text-sm font-semibold">Personas</h2>
            <.link
              id="new-persona"
              navigate={~p"/admin/assistant/personas/new"}
              class="btn btn-soft btn-sm"
            >
              <.icon name="hero-plus" class="size-4" /> New persona
            </.link>
          </div>
          <p :if={@personas == []} class="text-sm opacity-70">No personas yet.</p>
          <ul class="divide-y divide-base-300 rounded-xl border border-base-300">
            <li
              :for={persona <- @personas}
              id={"persona-#{persona.id}"}
              class="flex items-center gap-3 px-3 py-2 text-sm"
            >
              <.avatar
                name={persona.name}
                avatar_id={persona.avatar_id}
                assistant
                class="size-7 text-xs"
              />
              <span class="font-semibold">@{persona.name}</span>
              <span class="min-w-0 flex-1 truncate opacity-70">
                {if persona.rooms == [],
                  do: "in no rooms",
                  else: Enum.map_join(persona.rooms, ", ", &"##{&1}")}
              </span>
              <.link
                id={"edit-persona-#{persona.id}"}
                navigate={~p"/admin/assistant/personas/#{persona.id}/edit"}
                class="rounded-lg p-1.5 transition hover:bg-base-200"
                aria-label={"Edit @#{persona.name}"}
              >
                <.icon name="hero-pencil-square" class="size-4" />
              </.link>
              <button
                id={"delete-persona-#{persona.id}"}
                phx-click="delete_persona"
                phx-value-id={persona.id}
                data-confirm={"Delete @#{persona.name}? It leaves all its rooms."}
                class="rounded-lg p-1.5 text-error transition hover:bg-base-200"
                aria-label={"Delete @#{persona.name}"}
              >
                <.icon name="hero-trash" class="size-4" />
              </button>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "AI assistant")
     |> assign(:connection, nil)
     |> assign(:personas, Assistant.list_personas())
     |> assign_form(Assistant.change_settings(Assistant.get_settings()))}
  end

  @impl true
  def handle_event("validate", %{"settings" => params}, socket) do
    changeset =
      Assistant.get_settings()
      |> Assistant.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"settings" => params}, socket) do
    case Assistant.update_settings(socket.assigns.current_scope, params) do
      {:ok, settings} ->
        {:noreply,
         socket
         |> put_flash(:info, "Settings saved.")
         |> assign_form(Assistant.change_settings(settings))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  def handle_event("delete_persona", %{"id" => id}, socket) do
    persona = Assistant.get_persona!(id)
    {:ok, _} = Assistant.delete_persona(socket.assigns.current_scope, persona)

    {:noreply,
     socket
     |> put_flash(:info, "Deleted @#{persona.name}.")
     |> assign(:personas, Assistant.list_personas())}
  end

  def handle_event("test_connection", _params, socket) do
    connection =
      case Assistant.test_connection(socket.assigns.current_scope, socket.assigns.endpoint_url) do
        {:ok, info} -> {:ok, info}
        {:error, reason} -> {:error, describe_error(reason)}
      end

    {:noreply, assign(socket, :connection, connection)}
  end

  defp assign_form(socket, changeset) do
    socket
    |> assign(:form, to_form(changeset, as: :settings))
    |> assign(:endpoint_url, Ecto.Changeset.get_field(changeset, :endpoint_url))
  end

  # Names of personas whose worst-case prompt may not fit, or nil if all fit.
  defp oversized_personas(personas, context_length) do
    case for p <- personas, !Assistant.context_fits?(p, context_length), do: "@#{p.name}" do
      [] -> nil
      names -> names
    end
  end

  defp delimit(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp format_speed(speed), do: :erlang.float_to_binary(speed / 1, decimals: 1)

  defp describe_error(:econnrefused), do: "connection refused"
  defp describe_error(:timeout), do: "timed out"
  defp describe_error(:no_models), do: "the server serves no models"
  defp describe_error({:http_status, status}), do: "the server answered with HTTP #{status}"
  defp describe_error(reason), do: inspect(reason)
end
