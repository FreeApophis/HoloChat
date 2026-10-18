defmodule HoloChatWeb.TagComponents do
  @moduledoc """
  Tags on characters and scenes.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HoloChatWeb.Endpoint,
    router: HoloChatWeb.Router,
    statics: HoloChatWeb.static_paths()

  @doc """
  Renders tags as small pills. With `link`, each links to the character
  library filtered by that tag.
  """
  attr :tags, :list, required: true
  attr :link, :boolean, default: false
  attr :class, :any, default: nil

  def tags(assigns) do
    ~H"""
    <ul :if={@tags != []} class={["flex flex-wrap gap-1", @class]}>
      <li :for={tag <- @tags} data-tag={tag}>
        <%= if @link do %>
          <.link
            navigate={~p"/characters?#{[tag: tag]}"}
            class="block rounded-full bg-violet-500/10 px-2 py-0.5 text-xs font-medium text-violet-600 transition hover:bg-violet-500/20"
          >
            {tag}
          </.link>
        <% else %>
          <span class="block rounded-full bg-violet-500/10 px-2 py-0.5 text-xs font-medium text-violet-600">
            {tag}
          </span>
        <% end %>
      </li>
    </ul>
    """
  end
end
