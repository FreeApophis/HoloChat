defmodule HoloChat.Repo.Migrations.CreateCharacters do
  use Ecto.Migration

  # A library of characters, independent of any scene. Scenes cast them, and
  # shared tags (e.g. "harry-potter") suggest which characters fit a scene.
  def change do
    create table(:characters) do
      add :name, :string, null: false
      add :owner_id, references(:users, on_delete: :nilify_all)
      add :avatar_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
      add :tags, {:array, :string}, null: false, default: []
      add :description, :text
      add :personality, :text
      add :example_dialogue, :text

      timestamps(type: :utc_datetime)
    end

    create index(:characters, [:owner_id])
    create index(:characters, [:tags], using: :gin)

    alter table(:rooms) do
      add :tags, {:array, :string}, null: false, default: []
    end

    create table(:room_cast, primary_key: false) do
      add :room_id, references(:rooms, on_delete: :delete_all), null: false, primary_key: true

      add :character_id, references(:characters, on_delete: :delete_all),
        null: false,
        primary_key: true

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:room_cast, [:character_id])
  end
end
