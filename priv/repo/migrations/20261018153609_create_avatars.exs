defmodule HoloChat.Repo.Migrations.CreateAvatars do
  use Ecto.Migration

  # Processed avatar images (small JPEGs), kept apart from users and personas
  # so loading those never pulls image data. UUIDs make the public
  # /avatars/:id URLs unguessable and safe to cache forever.
  def change do
    create table(:avatars, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :content_type, :string, null: false
      add :data, :binary, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end
  end
end
