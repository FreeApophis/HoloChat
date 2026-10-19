defmodule HoloChat.Repo.Migrations.RequireAChannelForEveryScene do
  use Ecto.Migration

  # A scene is a room playing a scenario, so every room record has a name
  # again. Scenes created without a channel are dropped with their game
  # masters and cast (both cascade).
  def change do
    execute "DELETE FROM rooms WHERE name IS NULL", ""

    alter table(:rooms) do
      modify :name, :string, null: false, from: {:string, null: true}
    end
  end
end
