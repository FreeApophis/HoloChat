defmodule HoloChat.Repo.Migrations.AddUserIdToMessages do
  use Ecto.Migration

  def change do
    # Nullable: messages from before accounts existed have no author record.
    # `username` stays on the message as the name shown at posting time.
    alter table(:messages) do
      add :user_id, references(:users, on_delete: :nilify_all)
    end

    create index(:messages, [:user_id])
  end
end
