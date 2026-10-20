defmodule HoloChatWeb.NewsLive.Show do
  use HoloChatWeb, :live_view

  alias HoloChat.News

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <article id="post" class="mx-auto w-full max-w-3xl min-h-0 flex-1 overflow-y-auto py-6">
        <.link
          navigate={~p"/news"}
          class="inline-flex items-center gap-1 text-sm opacity-70 transition hover:opacity-100"
        >
          <.icon name="hero-arrow-left" class="size-4" /> All news
        </.link>

        <img
          :if={@post.cover_image_id}
          id="post-cover"
          src={~p"/avatars/#{@post.cover_image_id}"}
          alt=""
          class="mt-4 aspect-video w-full rounded-2xl object-cover shadow-md"
        />

        <header class="mt-6">
          <p class="flex items-center gap-2 text-xs font-medium tracking-wide uppercase opacity-60">
            <span
              :if={!@post.published_at}
              id="draft-badge"
              class="rounded-full bg-warning/20 px-2 py-0.5 text-warning"
            >
              Draft
            </span>
            <.post_date :if={@post.published_at} post={@post} />
            <span :if={@post.author}>
              · by <span id="post-author">{@post.author.username}</span>
            </span>
          </p>
          <h1 id="post-title" class="mt-2 text-3xl font-bold tracking-tight text-balance">
            {@post.title}
          </h1>
        </header>

        <div :if={@can_edit?} id="post-actions" class="mt-4 flex flex-wrap gap-2">
          <.link
            id="edit-post"
            navigate={~p"/news/#{@post.id}/edit"}
            class="btn btn-sm btn-soft"
          >
            <.icon name="hero-pencil-square" class="size-4" /> Edit
          </.link>
          <button
            :if={!@post.published_at}
            id="publish-post"
            phx-click="publish"
            class="btn btn-sm btn-primary"
          >
            <.icon name="hero-paper-airplane" class="size-4" /> Publish
          </button>
          <button
            :if={@post.published_at}
            id="unpublish-post"
            phx-click="unpublish"
            class="btn btn-sm btn-soft"
          >
            <.icon name="hero-eye-slash" class="size-4" /> Back to draft
          </button>
          <button
            id="delete-post"
            phx-click="delete"
            data-confirm="Delete this post for good?"
            class="btn btn-sm btn-ghost text-error"
          >
            <.icon name="hero-trash" class="size-4" /> Delete
          </button>
        </div>

        <.markdown id="post-body" text={@post.body} class="mt-6 leading-relaxed" />
      </article>
    </Layouts.app>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    scope = socket.assigns.current_scope

    case News.get_post(scope, id) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "That post doesn't exist.")
         |> redirect(to: ~p"/news")}

      post ->
        {:ok,
         socket
         |> assign(:page_title, post.title)
         |> assign(:can_edit?, News.can_edit?(scope))
         |> assign(:post, post)}
    end
  end

  @impl true
  def handle_event("publish", _params, socket) do
    change(socket, &News.publish_post(&1, &2), "Published.")
  end

  def handle_event("unpublish", _params, socket) do
    change(socket, &News.unpublish_post(&1, &2), "Moved back to drafts.")
  end

  def handle_event("delete", _params, socket) do
    case News.delete_post(socket.assigns.current_scope, socket.assigns.post) do
      {:ok, _post} ->
        {:noreply, socket |> put_flash(:info, "Post deleted.") |> push_navigate(to: ~p"/news")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "You can't delete this post.")}
    end
  end

  defp change(socket, fun, message) do
    %{current_scope: scope, post: post} = socket.assigns

    case fun.(scope, post) do
      {:ok, updated} ->
        {:noreply,
         socket
         |> put_flash(:info, message)
         |> assign(:post, %{updated | author: post.author})}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "You can't change this post.")}
    end
  end
end
