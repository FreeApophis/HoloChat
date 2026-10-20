defmodule HoloChat.Repo.Migrations.CreateNewsComments do
  use Ecto.Migration

  def change do
    create table(:news_comments) do
      add :body, :text, null: false
      add :post_id, references(:news_posts, on_delete: :delete_all), null: false
      add :author_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:news_comments, [:post_id, :inserted_at])
  end
end
