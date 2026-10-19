defmodule HoloChat.Repo.Migrations.LetScenesWaitForAChannel do
  use Ecto.Migration

  # A scene without a name waits for a channel to play in. The unique index
  # on the name allows any number of them.
  def change do
    alter table(:rooms) do
      modify :name, :string, null: true, from: {:string, null: false}
    end
  end
end
