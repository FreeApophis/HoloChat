defmodule HoloChat.Repo.Migrations.RemoveExampleDialogueFromCharacters do
  use Ecto.Migration

  # Models repeated example dialogue or took it for past events, so
  # characters no longer have any.
  def change do
    alter table(:characters) do
      remove :example_dialogue, :text
    end
  end
end
