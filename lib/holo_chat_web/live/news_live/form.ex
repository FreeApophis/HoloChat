defmodule HoloChatWeb.NewsLive.Form do
  use HoloChatWeb, :live_view

  alias HoloChat.News
  alias HoloChat.News.Post

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-2xl space-y-6 py-8">
        <.header>
          {@page_title}
          <:subtitle>
            Saved posts stay drafts until you publish them from the post's page.
          </:subtitle>
        </.header>

        <.form for={@form} id="post-form" phx-change="validate" phx-submit="save">
          <.input field={@form[:title]} type="text" label="Title" placeholder="Launch day" />
          <.input
            field={@form[:body]}
            type="textarea"
            label="Text"
            rows="14"
            placeholder="What's new? Markdown works."
          />

          <div class="mb-4 space-y-2 text-sm">
            <label class="font-medium" for={@uploads.cover_image.ref}>Cover image</label>
            <div class="aspect-video overflow-hidden rounded-lg bg-gradient-to-br from-cyan-500 via-sky-600 to-fuchsia-600">
              <%= case @uploads.cover_image.entries do %>
                <% [entry | _] -> %>
                  <.live_img_preview entry={entry} class="size-full object-cover" />
                <% [] -> %>
                  <img
                    :if={@post.cover_image_id}
                    src={~p"/avatars/#{@post.cover_image_id}"}
                    alt=""
                    class="size-full object-cover"
                  />
              <% end %>
            </div>
            <.live_file_input upload={@uploads.cover_image} class="file-input file-input-sm w-full" />
            <p class="text-xs opacity-60">
              Optional. Cropped to 16:9. PNG, JPEG or GIF, up to 8 MB.
            </p>
            <p :for={entry <- @uploads.cover_image.entries} class="text-xs">
              <span :for={error <- upload_errors(@uploads.cover_image, entry)} class="text-error">
                {upload_error(error)}
              </span>
            </p>
          </div>
          <p :if={@image_error} id="image-error" class="mb-3 text-sm text-error">{@image_error}</p>

          <.button variant="primary" phx-disable-with="Saving…">Save post</.button>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(params, _session, socket) do
    scope = socket.assigns.current_scope

    case load_post(socket.assigns.live_action, params, scope) do
      {:ok, post, title} ->
        {:ok,
         socket
         |> allow_upload(:cover_image,
           accept: ~w(.png .jpg .jpeg .gif),
           max_entries: 1,
           max_file_size: 8_000_000
         )
         |> assign(:page_title, title)
         |> assign(:image_error, nil)
         |> assign(:post, post)
         |> assign(:form, to_form(News.change_post(post)))}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, "Only news editors can write posts.")
         |> redirect(to: ~p"/news")}
    end
  end

  defp load_post(action, params, scope) do
    with true <- News.can_edit?(scope),
         {:ok, post} <- find_post(action, params, scope) do
      {:ok, post, if(post.id, do: "Edit #{post.title}", else: "New post")}
    else
      _missing_or_not_allowed -> :error
    end
  end

  defp find_post(:new, _params, _scope), do: {:ok, %Post{}}

  defp find_post(:edit, %{"id" => id}, scope) do
    case News.get_post(scope, id) do
      nil -> :error
      post -> {:ok, post}
    end
  end

  @impl true
  def handle_event("validate", %{"post" => params}, socket) do
    changeset =
      socket.assigns.post
      |> News.change_post(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"post" => params}, socket) do
    with {:ok, post} <- save_post(socket, params),
         {:ok, post} <- save_cover(socket, post) do
      {:noreply,
       socket
       |> put_flash(:info, "Post saved.")
       |> push_navigate(to: ~p"/news/#{post.id}")}
    else
      {:error, :invalid_image} ->
        {:noreply,
         assign(socket, :image_error, "The uploaded file could not be read as an image.")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, :unauthorized} ->
        {:noreply, put_flash(socket, :error, "Only news editors can write posts.")}
    end
  end

  defp save_post(%{assigns: %{post: %Post{id: nil}}} = socket, params),
    do: News.create_post(socket.assigns.current_scope, params)

  defp save_post(socket, params),
    do: News.update_post(socket.assigns.current_scope, socket.assigns.post, params)

  defp save_cover(socket, post) do
    images =
      consume_uploaded_entries(socket, :cover_image, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case images do
      [image] -> News.update_post_cover(socket.assigns.current_scope, post, image)
      [] -> {:ok, post}
    end
  end

  defp upload_error(:too_large), do: "Larger than 8 MB."
  defp upload_error(:not_accepted), do: "Not a PNG, JPEG or GIF."
  defp upload_error(:too_many_files), do: "Only one image at a time."
  defp upload_error(error), do: inspect(error)
end
