defmodule HoloChat.Repo.Migrations.CreateNewsPosts do
  use Ecto.Migration

  def change do
    # News editors write the posts on /news (admins may too).
    alter table(:users) do
      add :is_news_editor, :boolean, null: false, default: false
    end

    # A post without published_at is a draft, seen only by news editors.
    create table(:news_posts) do
      add :title, :string, null: false
      add :body, :text, null: false, default: ""
      add :published_at, :utc_datetime
      add :author_id, references(:users, on_delete: :nilify_all)
      add :cover_image_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:news_posts, [:published_at])
  end
end
