defmodule HoloChatWeb.AdminLive.Assistant do
  use HoloChatWeb, :live_view

  alias HoloChat.Assistant

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-xl space-y-6 overflow-y-auto py-6">
        <.header>
          AI assistant
          <:subtitle>
            The assistant idles in #lobby and answers messages that mention it as
            @{@name}. It needs an OpenAI-compatible server such as koboldcpp.
          </:subtitle>
        </.header>

        <.form
          for={@form}
          id="assistant-settings-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-1"
        >
          <.input field={@form[:enabled]} type="checkbox" label="Enabled" />
          <.input field={@form[:name]} type="text" label="Name" />

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
                  :if={!Assistant.context_fits?(@draft_settings, info.context_length)}
                  id="context-warning"
                  class="mt-2 text-warning"
                >
                  <.icon name="hero-exclamation-triangle" class="size-4" />
                  With {@draft_settings.context_messages} context messages and {@draft_settings.max_tokens} max tokens, a busy lobby can exceed this
                  model's context window. Lower one of them.
                </p>
              <% {:error, reason} -> %>
                <p class="text-error">
                  <.icon name="hero-x-circle" class="size-4" /> Could not connect: {reason}
                </p>
              <% nil -> %>
            <% end %>
          </div>

          <.input
            field={@form[:system_prompt]}
            type="textarea"
            label="System prompt ({name} is replaced with the assistant's name)"
            rows="6"
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

          <.button variant="primary" phx-disable-with="Saving…">Save settings</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    settings = Assistant.get_settings()

    {:ok,
     socket
     |> assign(:page_title, "AI assistant")
     |> assign(:connection, nil)
     |> assign_form(Assistant.change_settings(settings))}
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
    |> assign(:name, Ecto.Changeset.get_field(changeset, :name))
    |> assign(:endpoint_url, Ecto.Changeset.get_field(changeset, :endpoint_url))
    |> assign(:draft_settings, Ecto.Changeset.apply_changes(changeset))
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
