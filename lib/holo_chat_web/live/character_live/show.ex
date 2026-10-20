defmodule HoloChatWeb.CharacterLive.Show do
  use HoloChatWeb, :live_view

  alias HoloChat.Characters

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-2xl overflow-y-auto py-6">
        <.link navigate={~p"/characters"} class="text-sm opacity-60 hover:underline">
          ← All characters
        </.link>

        <div class="mt-4 flex flex-wrap items-start gap-5">
          <div id="character-avatar">
            <.avatar
              name={@character.name}
              avatar_id={@character.avatar_id}
              class="size-28 text-4xl shadow-md"
            />
          </div>
          <div class="min-w-0 flex-1 space-y-2">
            <h1 id="character-name" class="text-2xl font-semibold tracking-tight">
              {@character.name}
            </h1>
            <.tags tags={@character.tags} link />
            <div :if={@can_edit?} class="flex gap-2 pt-1">
              <.link
                id="edit-character-link"
                navigate={~p"/characters/#{@character.id}/edit"}
                class="flex items-center gap-1 rounded-lg border border-base-300 px-3 py-1.5 text-sm transition hover:bg-base-200"
              >
                <.icon name="hero-pencil-square" class="size-4" /> Edit
              </.link>
              <button
                id="delete-character"
                type="button"
                phx-click="delete"
                data-confirm="Delete this character? It is removed from every scene."
                class="flex items-center gap-1 rounded-lg px-3 py-1.5 text-sm text-error transition hover:bg-error/10"
              >
                <.icon name="hero-trash" class="size-4" /> Delete
              </button>
            </div>
          </div>
        </div>

        <div class="mt-8 space-y-6">
          <.sheet_section
            id="character-description"
            title="Description"
            text={@character.description}
          />
          <.sheet_section
            id="character-personality"
            title="Personality"
            text={@character.personality}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :text, :string, default: nil

  defp sheet_section(assigns) do
    ~H"""
    <section :if={@text not in [nil, ""]}>
      <h2 class="mb-1 text-xs font-semibold uppercase tracking-wide opacity-60">{@title}</h2>
      <.markdown id={@id} text={@text} class="text-sm leading-relaxed" />
    </section>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Characters.get_character(id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That character doesn't exist.")
         |> push_navigate(to: ~p"/characters")}

      character ->
        {:ok,
         socket
         |> assign(:page_title, character.name)
         |> assign(:character, character)
         |> assign(:can_edit?, Characters.can_edit?(socket.assigns.current_scope, character))}
    end
  end

  @impl true
  def handle_event("delete", _params, socket) do
    case Characters.delete_character(socket.assigns.current_scope, socket.assigns.character) do
      {:ok, _character} ->
        {:noreply,
         socket
         |> put_flash(:info, "Character deleted.")
         |> push_navigate(to: ~p"/characters")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "You can't delete this character.")}
    end
  end
end
