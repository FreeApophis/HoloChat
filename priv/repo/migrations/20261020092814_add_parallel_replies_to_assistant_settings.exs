defmodule HoloChat.Repo.Migrations.AddParallelRepliesToAssistantSettings do
  use Ecto.Migration

  def change do
    alter table(:assistant_settings) do
      add :parallel_replies, :integer, null: false, default: 1
    end
  end
end
