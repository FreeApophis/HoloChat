defmodule HoloChat.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  # Rooms without a record are plain chat rooms (just a name on messages).
  # A record gives a room a kind, game masters and a scene.
  def change do
    create table(:rooms) do
      add :name, :string, null: false
      add :kind, :string, null: false, default: "roleplay"
      add :title, :string, null: false
      add :topic, :string
      add :scenario, :text
      add :card_image_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
      add :background_image_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create unique_index(:rooms, [:name])
    create index(:rooms, [:kind])

    create table(:room_masters, primary_key: false) do
      add :room_id, references(:rooms, on_delete: :delete_all), null: false, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false, primary_key: true

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:room_masters, [:user_id])
  end
end
