defmodule HoloChat.Repo.Migrations.CreateMessages do
  use Ecto.Migration

  def change do
    create table(:messages) do
      add :room, :string, null: false
      add :username, :string, null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:messages, [:room, :inserted_at])
  end
end
