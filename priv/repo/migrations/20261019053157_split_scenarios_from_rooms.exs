defmodule HoloChat.Repo.Migrations.SplitScenariosFromRooms do
  use Ecto.Migration

  # Scenarios become a library of their own. A role-play room plays one
  # scenario at a time and can switch; each switch is a message in the chat.
  # Existing rooms keep their scene as a scenario owned by their first game
  # master, with their cast as its suggested cast.
  def up do
    create table(:scenarios) do
      add :title, :string, null: false
      add :topic, :string
      add :description, :text
      add :tags, {:array, :string}, null: false, default: []
      add :owner_id, references(:users, on_delete: :nilify_all)
      add :card_image_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
      add :background_image_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
      add :from_room_id, :bigint

      timestamps(type: :utc_datetime)
    end

    create index(:scenarios, [:owner_id])
    create index(:scenarios, [:tags], using: :gin)

    create table(:scenario_cast, primary_key: false) do
      add :scenario_id, references(:scenarios, on_delete: :delete_all),
        null: false,
        primary_key: true

      add :character_id, references(:characters, on_delete: :delete_all),
        null: false,
        primary_key: true

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:scenario_cast, [:character_id])

    alter table(:rooms) do
      add :scenario_id, references(:scenarios, on_delete: :nilify_all)
    end

    create index(:rooms, [:scenario_id])

    # "chat" for ordinary messages; "scenario" announces a scenario change.
    alter table(:messages) do
      add :kind, :string, null: false, default: "chat"
      add :scenario_id, references(:scenarios, on_delete: :nilify_all)
    end

    flush()

    execute """
    INSERT INTO scenarios (title, topic, description, tags, owner_id, card_image_id,
                           background_image_id, from_room_id, inserted_at, updated_at)
    SELECT r.title, r.topic, r.scenario, r.tags,
           (SELECT gm.user_id FROM room_masters gm WHERE gm.room_id = r.id
            ORDER BY gm.inserted_at, gm.user_id LIMIT 1),
           r.card_image_id, r.background_image_id, r.id, r.inserted_at, r.updated_at
    FROM rooms r
    """

    execute "UPDATE rooms SET scenario_id = s.id FROM scenarios s WHERE s.from_room_id = rooms.id"

    execute """
    INSERT INTO scenario_cast (scenario_id, character_id, inserted_at)
    SELECT s.id, rc.character_id, rc.inserted_at
    FROM room_cast rc JOIN scenarios s ON s.from_room_id = rc.room_id
    """

    alter table(:scenarios) do
      remove :from_room_id
    end

    alter table(:rooms) do
      remove :title
      remove :topic
      remove :scenario
      remove :tags
      remove :card_image_id
      remove :background_image_id
    end
  end

  # Puts each room's current scenario back on the room. Scenarios no room
  # plays and the scenario-change messages are lost.
  def down do
    alter table(:rooms) do
      add :title, :string
      add :topic, :string
      add :scenario, :text
      add :tags, {:array, :string}, null: false, default: []
      add :card_image_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
      add :background_image_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
    end

    flush()

    execute """
    UPDATE rooms SET title = COALESCE(s.title, rooms.name), topic = s.topic,
                     scenario = s.description, tags = COALESCE(s.tags, '{}'),
                     card_image_id = s.card_image_id,
                     background_image_id = s.background_image_id
    FROM rooms r LEFT JOIN scenarios s ON s.id = r.scenario_id
    WHERE r.id = rooms.id
    """

    execute "ALTER TABLE rooms ALTER COLUMN title SET NOT NULL"
    execute "DELETE FROM messages WHERE kind = 'scenario'"

    alter table(:messages) do
      remove :kind
      remove :scenario_id
    end

    alter table(:rooms) do
      remove :scenario_id
    end

    drop table(:scenario_cast)
    drop table(:scenarios)
  end
end
