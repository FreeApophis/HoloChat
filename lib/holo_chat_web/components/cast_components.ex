defmodule HoloChatWeb.CastComponents do
  @moduledoc """
  Picking a cast from the character library, for rooms and scenarios.

  The LiveView handles the events `"cast"` and `"uncast"` (with the
  character's `"id"`) and `"search"` (with `%{"search" => %{"query" => ...}}`).
  """
  use Phoenix.Component

  import HoloChatWeb.CoreComponents
  import HoloChatWeb.AvatarComponents
  import HoloChatWeb.TagComponents

  @doc """
  Renders the cast, suggested characters and a search for more.
  """
  attr :cast, :list, required: true
  attr :suggestions, :list, required: true
  attr :search_form, Phoenix.HTML.Form, required: true
  attr :search_results, :list, required: true
  attr :tags, :list, required: true, doc: "the tags suggestions are matched on"

  def cast_editor(assigns) do
    ~H"""
    <ul
      :if={@cast != []}
      id="cast-members"
      class="divide-y divide-base-300 rounded-xl border border-base-300"
    >
      <li
        :for={character <- @cast}
        id={"cast-member-#{character.id}"}
        class="flex items-center gap-3 px-3 py-2"
      >
        <.avatar name={character.name} avatar_id={character.avatar_id} class="size-8 text-xs" />
        <span class="flex-1 text-sm font-medium">{character.name}</span>
        <button
          id={"uncast-#{character.id}"}
          type="button"
          phx-click="uncast"
          phx-value-id={character.id}
          class="rounded-lg px-2 py-1 text-xs opacity-70 transition hover:bg-base-200 hover:opacity-100"
        >
          Remove
        </button>
      </li>
    </ul>
    <p :if={@cast == []} id="cast-empty" class="text-sm opacity-60">
      Nobody is cast yet.
    </p>

    <div :if={@suggestions != []} id="suggested-characters" class="space-y-2">
      <h3 class="text-sm font-semibold">Suggested by tags</h3>
      <div class="grid gap-2 sm:grid-cols-2">
        <.cast_candidate
          :for={character <- @suggestions}
          id={"suggestion-#{character.id}"}
          character={character}
          tags={@tags}
        />
      </div>
    </div>

    <.form for={@search_form} id="cast-search-form" phx-change="search" phx-submit="search">
      <.input
        field={@search_form[:query]}
        type="search"
        placeholder="Find any character by name…"
        autocomplete="off"
        phx-debounce="250"
      />
    </.form>
    <div :if={@search_results != []} id="search-results" class="grid gap-2 sm:grid-cols-2">
      <.cast_candidate
        :for={character <- @search_results}
        id={"search-result-#{character.id}"}
        character={character}
        tags={@tags}
      />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :character, :map, required: true
  attr :tags, :list, required: true

  defp cast_candidate(assigns) do
    ~H"""
    <div id={@id} class="flex items-center gap-3 rounded-xl border border-base-300 p-2">
      <.avatar name={@character.name} avatar_id={@character.avatar_id} class="size-9 text-sm" />
      <div class="min-w-0 flex-1">
        <p class="truncate text-sm font-medium">{@character.name}</p>
        <.tags tags={Enum.filter(@character.tags, &(&1 in @tags))} />
      </div>
      <button
        id={"cast-#{@character.id}"}
        type="button"
        phx-click="cast"
        phx-value-id={@character.id}
        class="flex items-center gap-1 rounded-lg bg-primary/10 px-2 py-1 text-xs font-medium text-primary transition hover:bg-primary/20"
      >
        <.icon name="hero-plus" class="size-3.5" /> Cast
      </button>
    </div>
    """
  end
end
