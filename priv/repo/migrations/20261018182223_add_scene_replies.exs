defmodule HoloChat.Repo.Migrations.AddSceneReplies do
  use Ecto.Migration

  def change do
    # Messages written by a cast character (played by the model).
    alter table(:messages) do
      add :character_id, references(:characters, on_delete: :nilify_all)
    end

    # How the cast takes turns, chosen by the game masters.
    alter table(:rooms) do
      add :reply_policy, :string, null: false, default: "natural"
      add :reply_delay, :integer, null: false, default: 4
      add :max_ai_turns, :integer, null: false, default: 2
    end
  end
end
