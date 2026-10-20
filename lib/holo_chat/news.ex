defmodule HoloChat.News do
  @moduledoc """
  The News context: the site's blog.

  News editors (and admins) write posts in Markdown, with an optional cover
  image. A post is a draft, seen only by news editors, until it is published.
  """

  use Boundary, deps: [HoloChat.Repo, HoloChat.Accounts, HoloChat.Avatars], exports: [Post]

  import Ecto.Query, warn: false

  alias HoloChat.{Accounts, Avatars}
  alias HoloChat.Accounts.{Scope, User}
  alias HoloChat.News.Post
  alias HoloChat.Repo

  @cover_size {1280, 720}

  @doc """
  Returns published posts with their authors, newest first, at most `limit`.
  """
  def list_published_posts(limit \\ 50) do
    Repo.all(
      from p in Post,
        where: not is_nil(p.published_at),
        order_by: [desc: p.published_at, desc: p.id],
        limit: ^limit,
        preload: :author
    )
  end

  @doc """
  Returns the drafts, newest first, for news editors; `[]` for everyone else.
  """
  def list_drafts(scope) do
    if Accounts.news_editor?(scope) do
      Repo.all(
        from p in Post,
          where: is_nil(p.published_at),
          order_by: [desc: p.updated_at, desc: p.id],
          preload: :author
      )
    else
      []
    end
  end

  @doc """
  Gets a post with its author. Drafts are only returned to news editors;
  nil if the post doesn't exist, isn't visible or the id is malformed.
  """
  def get_post(scope, id) do
    with {:ok, id} <- Ecto.Type.cast(:id, id),
         %Post{} = post <- Repo.get(Post, id),
         true <- post.published_at != nil or Accounts.news_editor?(scope) do
      Repo.preload(post, :author)
    else
      _missing_or_hidden -> nil
    end
  end

  @doc """
  Returns true if the scope may write, publish and delete posts.
  """
  def can_edit?(scope), do: Accounts.news_editor?(scope)

  @doc """
  Returns a changeset for tracking post changes.
  """
  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

  @doc """
  Creates a draft written by the scope's user.
  """
  def create_post(scope, attrs) do
    authorize(scope, fn ->
      %Post{author_id: author_id(scope)} |> Post.changeset(attrs) |> Repo.insert()
    end)
  end

  @doc """
  Updates the post's title and text.
  """
  def update_post(scope, %Post{} = post, attrs) do
    authorize(scope, fn -> post |> Post.changeset(attrs) |> Repo.update() end)
  end

  @doc """
  Publishes the post, dated `now`.
  """
  def publish_post(scope, %Post{} = post, now \\ DateTime.utc_now()) do
    authorize(scope, fn ->
      post
      |> Ecto.Changeset.change(published_at: DateTime.truncate(now, :second))
      |> Repo.update()
    end)
  end

  @doc """
  Makes a published post a draft again.
  """
  def unpublish_post(scope, %Post{} = post) do
    authorize(scope, fn -> post |> Ecto.Changeset.change(published_at: nil) |> Repo.update() end)
  end

  @doc """
  Replaces the post's cover (cropped to 16:9) with an uploaded image,
  deleting the old one. `{:error, :invalid_image}` keeps the current cover.
  """
  def update_post_cover(scope, %Post{} = post, image) when is_binary(image) do
    authorize(scope, fn -> Repo.transact(fn -> replace_cover(post, image) end) end)
  end

  defp replace_cover(post, image) do
    with {:ok, cover} <- Avatars.create_avatar(image, @cover_size),
         {:ok, updated} <-
           post |> Ecto.Changeset.change(cover_image_id: cover.id) |> Repo.update() do
      :ok = Avatars.delete_avatar(post.cover_image_id)
      {:ok, updated}
    end
  end

  @doc """
  Deletes the post and its cover image.
  """
  def delete_post(scope, %Post{} = post) do
    authorize(scope, fn -> Repo.transact(fn -> delete_with_cover(post) end) end)
  end

  defp delete_with_cover(post) do
    with {:ok, deleted} <- Repo.delete(post) do
      :ok = Avatars.delete_avatar(post.cover_image_id)
      {:ok, deleted}
    end
  end

  defp author_id(%Scope{user: %User{id: id}}), do: id

  defp authorize(scope, fun) do
    if can_edit?(scope), do: fun.(), else: {:error, :unauthorized}
  end
end
