defmodule HoloChatWeb.MarkdownComponents do
  @moduledoc """
  User-written text rendered as Markdown; styled by `.markdown` in `app.css`.
  """
  use Phoenix.Component

  alias HoloChatWeb.Markdown

  attr :text, :string, default: nil
  attr :room_links, :atom, default: :navigate, values: [:navigate, :patch]
  attr :class, :any, default: nil
  attr :rest, :global

  def markdown(assigns) do
    ~H"""
    <div class={["markdown", @class]} {@rest}>{Markdown.to_html(@text, room_links: @room_links)}</div>
    """
  end
end
