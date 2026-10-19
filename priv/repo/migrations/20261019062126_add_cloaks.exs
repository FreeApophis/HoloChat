defmodule HoloChat.Repo.Migrations.AddCloaks do
  use Ecto.Migration

  # A cloak is the library character a player wears in one room. Rooms are
  # names here, since chat rooms have no record. A character is worn by at
  # most one player per room. Messages already carry `character_id`; on a
  # player's message it is the cloak worn when it was written.
  def change do
    create table(:cloaks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :room, :string, null: false
      add :character_id, references(:characters, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:cloaks, [:user_id, :room])
    create unique_index(:cloaks, [:room, :character_id])
    create index(:cloaks, [:character_id])

    # What happens when a player wears a character the AI plays in the room:
    # "takeover" (the AI steps aside) or "forbid".
    alter table(:rooms) do
      add :cloak_policy, :string, null: false, default: "takeover"
    end
  end
end
