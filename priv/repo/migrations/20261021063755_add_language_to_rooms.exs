defmodule HoloChat.Repo.Migrations.AddLanguageToRooms do
  use Ecto.Migration

  def change do
    # The language spoken in the room, which the AI follows ("en", "de").
    alter table(:rooms) do
      add :language, :string, null: false, default: "en"
    end
  end
end
