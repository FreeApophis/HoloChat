defmodule HoloChat.News.Post do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # A post without `published_at` is a draft.
  schema "news_posts" do
    field :title, :string
    field :body, :string, default: ""
    field :published_at, :utc_datetime
    field :cover_image_id, :binary_id
    belongs_to :author, HoloChat.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for the post's text. The author, cover and publication date are
  set by the server, never cast.
  """
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :body])
    |> update_change(:title, &String.trim/1)
    # A cleared body is empty text, not NULL.
    |> update_change(:body, &(&1 || ""))
    |> validate_required([:title])
    |> validate_length(:title, max: 120)
    |> validate_length(:body, max: 20_000)
  end
end
