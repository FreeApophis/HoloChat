defmodule HoloChatWeb.NewsLive.Index do
  use HoloChatWeb, :live_view

  alias HoloChat.News

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="min-h-0 flex-1 overflow-y-auto">
        <div class="mb-6 flex flex-wrap items-end justify-between gap-4">
          <div>
            <h1 class="flex items-center gap-2 text-2xl font-semibold tracking-tight">
              <.icon name="hero-newspaper" class="size-6 text-primary" /> News
            </h1>
            <p class="mt-1 text-sm opacity-70">Updates, events and changes on HoloChat.</p>
          </div>
          <.link
            :if={@can_edit?}
            id="new-post"
            navigate={~p"/news/new"}
            class="flex items-center gap-1.5 rounded-lg bg-primary px-3 py-2 text-sm font-medium text-primary-content shadow-sm transition hover:opacity-90"
          >
            <.icon name="hero-plus" class="size-4" /> New post
          </.link>
        </div>

        <section
          :if={@drafts != []}
          id="drafts"
          class="mb-8 rounded-2xl border border-dashed border-base-300 p-4"
        >
          <h2 class="mb-2 text-sm font-semibold tracking-wide uppercase opacity-60">Drafts</h2>
          <ul class="divide-y divide-base-300">
            <li :for={draft <- @drafts} id={"draft-#{draft.id}"} class="py-2">
              <.link
                navigate={~p"/news/#{draft.id}"}
                class="flex items-center justify-between gap-3 rounded-lg px-2 py-1 transition hover:bg-base-200"
              >
                <span class="font-medium">{draft.title}</span>
                <span class="text-xs opacity-60">
                  {Calendar.strftime(draft.updated_at, "%B %-d, %Y")}
                </span>
              </.link>
            </li>
          </ul>
        </section>

        <div
          :if={@posts == []}
          id="no-posts"
          class="flex flex-col items-center gap-2 rounded-2xl border border-dashed border-base-300 py-16 text-center opacity-70"
        >
          <.icon name="hero-newspaper" class="size-8" />
          <p class="text-sm">No news yet.</p>
        </div>

        <div id="published-posts" class="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          <.post_card :for={post <- @posts} id={"post-#{post.id}"} post={post} />
        </div>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    scope = socket.assigns.current_scope

    {:ok,
     socket
     |> assign(:page_title, "News")
     |> assign(:can_edit?, News.can_edit?(scope))
     |> assign(:drafts, News.list_drafts(scope))
     |> assign(:posts, News.list_published_posts())}
  end
end
