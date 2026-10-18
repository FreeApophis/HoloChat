defmodule HoloChat.Repo.Migrations.AddProfileToPersonas do
  use Ecto.Migration

  def change do
    alter table(:assistant_personas) do
      add :avatar_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
      # Public, unlike the system prompt.
      add :description, :text
    end

    # Which persona wrote an assistant message, so its current profile can be
    # shown even after a rename.
    alter table(:messages) do
      add :persona_id, references(:assistant_personas, on_delete: :nilify_all)
    end

    create index(:messages, [:persona_id])
  end
end
