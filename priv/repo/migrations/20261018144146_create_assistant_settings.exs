defmodule HoloChat.Repo.Migrations.CreateAssistantSettings do
  use Ecto.Migration

  # A single row (id 1) holding the assistant's configuration.
  def change do
    create table(:assistant_settings) do
      add :enabled, :boolean, null: false, default: false
      add :name, :string, null: false
      add :endpoint_url, :string, null: false
      add :system_prompt, :text, null: false
      add :context_messages, :integer, null: false
      add :max_tokens, :integer, null: false
      add :temperature, :float, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
