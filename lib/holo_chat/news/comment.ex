defmodule HoloChat.News.Comment do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "news_comments" do
    field :body, :string
    field :post_id, :id
    belongs_to :author, HoloChat.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for the comment's text. The post and author are set by the
  server, never cast.
  """
  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, max: 2000)
  end
end
