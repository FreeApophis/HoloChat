defmodule HoloChat.Repo.Migrations.AddFromAssistantToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :from_assistant, :boolean, null: false, default: false
    end
  end
end
