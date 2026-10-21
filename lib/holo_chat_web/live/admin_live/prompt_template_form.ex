defmodule HoloChatWeb.AdminLive.PromptTemplateForm do
  use HoloChatWeb, :live_view

  alias HoloChat.Assistant
  alias HoloChat.Assistant.PromptTemplate

  @placeholders [
    {"{{char}}", "the character's name"},
    {"{{description}}", "the character's description"},
    {"{{personality}}", "the character's personality"},
    {"{{scenario_title}}", "the title of the scenario the room plays"},
    {"{{scenario}}", "the scenario's description"},
    {"{{others}}",
     "who else is in the scene: the other cast characters and the players who spoke, one per line"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-2xl space-y-6 py-6">
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
          id="prompt-template-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-1"
        >
          <.input field={@form[:name]} type="text" label="Name (shown to game masters)" />
          <.input
            field={@form[:body]}
            type="textarea"
            label="System prompt for cast characters"
            rows="18"
            class="w-full textarea font-mono text-xs leading-relaxed"
          />

          <div id="placeholder-help" class="mb-4 rounded-xl bg-base-200/60 p-3 text-xs">
            <p class="mb-2 font-medium">Placeholders</p>
            <dl class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1">
              <%= for {placeholder, meaning} <- @placeholders do %>
                <dt class="font-mono">{placeholder}</dt>
                <dd class="opacity-70">{meaning}</dd>
              <% end %>
            </dl>
            <p class="mt-2 opacity-70">
              A line whose placeholders are all empty is left out, and so is a paragraph
              that loses all such lines, so a "Personality:" label disappears with an
              empty personality. The chat itself follows as messages.
            </p>
          </div>

          <.button variant="primary" phx-disable-with="Saving…">Save template</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    {template, attrs} =
      case socket.assigns.live_action do
        :new -> {%PromptTemplate{}, %{"body" => Assistant.default_prompt_template()}}
        :edit -> {Assistant.get_prompt_template(params["id"]), %{}}
      end

    case template do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That template no longer exists.")
         |> push_navigate(to: ~p"/admin/assistant")}

      template ->
        {:ok,
         socket
         |> assign(:template, template)
         |> assign(:placeholders, @placeholders)
         |> assign(:page_title, page_title(socket.assigns.live_action, template))
         |> assign_form(Assistant.change_prompt_template(template, attrs))}
    end
  end

  @impl true
  def handle_event("validate", %{"prompt_template" => params}, socket) do
    changeset =
      socket.assigns.template
      |> Assistant.change_prompt_template(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"prompt_template" => params}, socket) do
    case save(socket, params) do
      {:ok, _template} ->
        {:noreply,
         socket
         |> put_flash(:info, "Template saved.")
         |> push_navigate(to: ~p"/admin/assistant")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save(%{assigns: %{live_action: :new}} = socket, params) do
    Assistant.create_prompt_template(socket.assigns.current_scope, params)
  end

  defp save(%{assigns: %{live_action: :edit}} = socket, params) do
    Assistant.update_prompt_template(
      socket.assigns.current_scope,
      socket.assigns.template,
      params
    )
  end

  defp assign_form(socket, changeset),
    do: assign(socket, :form, to_form(changeset, as: :prompt_template))

  defp page_title(:new, _template), do: "New prompt template"
  defp page_title(:edit, template), do: "Edit #{template.name}"
end
