defmodule HoloChat.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users) do
      add :username, :citext, null: false
      add :hashed_password, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    # Kept apart from users_tokens: password changes expire every token,
    # but must leave recovery codes intact.
    create table(:users_recovery_codes) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :hashed_code, :binary, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_recovery_codes, [:user_id])
    create unique_index(:users_recovery_codes, [:hashed_code])
  end
end
