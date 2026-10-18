defmodule HoloChat.Repo.Migrations.CreateAssistantPersonas do
  use Ecto.Migration

  # Moves the assistant's identity out of the global settings into personas,
  # which can live in several rooms. An existing configuration becomes a
  # persona with the same name, placed in the lobby.
  def up do
    create table(:assistant_personas) do
      add :name, :citext, null: false
      add :system_prompt, :text, null: false
      add :context_messages, :integer, null: false
      add :max_tokens, :integer, null: false
      add :temperature, :float, null: false
      add :rooms, {:array, :string}, null: false, default: []

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assistant_personas, [:name])

    execute """
    INSERT INTO assistant_personas
      (name, system_prompt, context_messages, max_tokens, temperature, rooms, inserted_at, updated_at)
    SELECT name, system_prompt, context_messages, max_tokens, temperature, ARRAY['lobby'], now(), now()
    FROM assistant_settings
    """

    alter table(:assistant_settings) do
      remove :name
      remove :system_prompt
      remove :context_messages
      remove :max_tokens
      remove :temperature
    end
  end

  def down do
    alter table(:assistant_settings) do
      add :name, :string, null: false, default: "Holo"
      add :system_prompt, :text, null: false, default: ""
      add :context_messages, :integer, null: false, default: 20
      add :max_tokens, :integer, null: false, default: 512
      add :temperature, :float, null: false, default: 0.7
    end

    execute """
    UPDATE assistant_settings s
    SET name = p.name, system_prompt = p.system_prompt, context_messages = p.context_messages,
        max_tokens = p.max_tokens, temperature = p.temperature
    FROM (SELECT * FROM assistant_personas ORDER BY id LIMIT 1) p
    """

    drop table(:assistant_personas)
  end
end
