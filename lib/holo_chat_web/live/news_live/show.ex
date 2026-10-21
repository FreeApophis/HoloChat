defmodule HoloChatWeb.NewsLive.Show do
  use HoloChatWeb, :live_view

  alias HoloChat.News
  alias HoloChat.News.Comment

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <article id="post" class="mx-auto w-full max-w-3xl py-6">
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

        <section
          :if={@post.published_at}
          id="post-comments"
          class="mt-12 border-t border-base-300 pt-6"
        >
          <h2 class="flex items-center gap-2 text-lg font-semibold">
            <.icon name="hero-chat-bubble-oval-left" class="size-5 text-primary" /> Comments
          </h2>

          <ol id="comments" phx-update="stream" class="mt-4 space-y-4">
            <li id="no-comments" class="hidden text-sm opacity-60 only:block">
              No comments yet.
            </li>
            <li :for={{id, comment} <- @streams.comments} id={id} class="group flex gap-3">
              <.avatar
                name={comment.author.username}
                avatar_id={comment.author.avatar_id}
                class="size-8 shrink-0 text-xs"
              />
              <div class="min-w-0 flex-1">
                <p class="flex items-center gap-2 text-sm">
                  <span class="font-medium">{comment.author.username}</span>
                  <time
                    datetime={DateTime.to_iso8601(comment.inserted_at)}
                    class="text-xs opacity-60"
                  >
                    {Calendar.strftime(comment.inserted_at, "%B %-d, %Y %H:%M")}
                  </time>
                  <button
                    :if={News.can_delete_comment?(@current_scope, comment)}
                    id={"delete-comment-#{comment.id}"}
                    phx-click="delete_comment"
                    phx-value-id={comment.id}
                    data-confirm="Delete this comment?"
                    class="ml-auto rounded p-1 opacity-0 transition group-hover:opacity-60 hover:!opacity-100 focus:opacity-100"
                    aria-label="Delete comment"
                    title="Delete comment"
                  >
                    <.icon name="hero-trash" class="size-4" />
                  </button>
                </p>
                <.markdown text={comment.body} class="mt-0.5 text-sm leading-relaxed" />
              </div>
            </li>
          </ol>

          <.form
            :if={@current_scope}
            for={@comment_form}
            id="comment-form"
            phx-submit="comment"
            class="mt-6"
          >
            <.input
              field={@comment_form[:body]}
              type="textarea"
              rows="3"
              placeholder="Write a comment… Markdown works."
            />
            <.button variant="primary" phx-disable-with="Sending…">Comment</.button>
          </.form>
          <p :if={!@current_scope} class="mt-6 text-sm opacity-70">
            <.link id="comment-login" navigate={~p"/users/log-in"} class="font-medium text-primary">
              Log in
            </.link>
            to comment.
          </p>
        </section>
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
        if connected?(socket), do: News.subscribe_comments(post)

        {:ok,
         socket
         |> assign(:page_title, post.title)
         |> assign(:can_edit?, News.can_edit?(scope))
         |> assign(:post, post)
         |> assign_comment_form()
         |> stream(:comments, News.list_comments(post))}
    end
  end

  @impl true
  def handle_info({:comment_created, comment}, socket),
    do: {:noreply, stream_insert(socket, :comments, comment)}

  def handle_info({:comment_deleted, comment}, socket),
    do: {:noreply, stream_delete(socket, :comments, comment)}

  defp assign_comment_form(socket, changeset \\ News.change_comment(%Comment{})) do
    assign(socket, :comment_form, to_form(changeset))
  end

  @impl true
  def handle_event("publish", _params, socket) do
    change(socket, &News.publish_post(&1, &2), "Published.")
  end

  def handle_event("unpublish", _params, socket) do
    change(socket, &News.unpublish_post(&1, &2), "Moved back to drafts.")
  end

  # The new comment arrives through the subscription, like everyone else's.
  def handle_event("comment", %{"comment" => params}, socket) do
    case News.create_comment(socket.assigns.current_scope, socket.assigns.post, params) do
      {:ok, _comment} ->
        {:noreply, assign_comment_form(socket)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_comment_form(socket, changeset)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "You can't comment on this post.")}
    end
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    comment = Enum.find(News.list_comments(socket.assigns.post), &(to_string(&1.id) == id))

    case comment && News.delete_comment(socket.assigns.current_scope, comment) do
      {:ok, _comment} ->
        {:noreply, socket}

      _missing_or_refused ->
        {:noreply, put_flash(socket, :error, "You can't delete this comment.")}
    end
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
