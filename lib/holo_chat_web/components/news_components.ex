defmodule HoloChatWeb.NewsComponents do
  @moduledoc """
  News posts as cards, on `/news` and the landing page.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HoloChatWeb.Endpoint,
    router: HoloChatWeb.Router,
    statics: HoloChatWeb.static_paths()

  import HoloChatWeb.MarkdownComponents

  attr :id, :string, required: true
  attr :post, :any, required: true
  attr :class, :any, default: nil

  @doc "A post's cover, title, date and the start of its text, linking to the post."
  def post_card(assigns) do
    ~H"""
    <article
      id={@id}
      class={[
        "group relative flex flex-col overflow-hidden rounded-2xl border border-base-300 bg-base-100 shadow-sm transition hover:-translate-y-0.5 hover:shadow-lg",
        @class
      ]}
    >
      <div class="aspect-video overflow-hidden bg-gradient-to-br from-cyan-500 via-sky-600 to-fuchsia-600">
        <img
          :if={@post.cover_image_id}
          src={~p"/avatars/#{@post.cover_image_id}"}
          alt=""
          class="size-full object-cover transition duration-500 group-hover:scale-105"
        />
      </div>
      <div class="flex flex-1 flex-col p-5">
        <p class="text-xs font-medium tracking-wide uppercase opacity-60">
          <.post_date post={@post} />
        </p>
        <h3 class="mt-1 text-lg font-semibold tracking-tight">
          <.link navigate={~p"/news/#{@post.id}"} class="after:absolute after:inset-0">
            {@post.title}
          </.link>
        </h3>
        <.markdown text={@post.body} class="mt-2 line-clamp-3 text-sm leading-relaxed opacity-75" />
      </div>
    </article>
    """
  end

  attr :post, :any, required: true

  @doc "The publication date, or \"Draft\"."
  def post_date(assigns) do
    ~H"""
    <%= if @post.published_at do %>
      <time datetime={DateTime.to_iso8601(@post.published_at)}>
        {Calendar.strftime(@post.published_at, "%B %-d, %Y")}
      </time>
    <% else %>
      Draft
    <% end %>
    """
  end
end
