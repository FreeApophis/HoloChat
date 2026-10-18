defmodule HoloChat.Repo.Migrations.AddProfileToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :avatar_id, references(:avatars, type: :binary_id, on_delete: :nilify_all)
      add :description, :text
    end
  end
end
