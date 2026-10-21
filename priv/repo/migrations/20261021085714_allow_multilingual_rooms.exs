defmodule HoloChat.Repo.Migrations.AllowMultilingualRooms do
  use Ecto.Migration

  def change do
    # No language: the room is multilingual, like rooms without a record.
    alter table(:rooms) do
      modify :language, :string,
        null: true,
        default: "en",
        from: {:string, null: false, default: "en"}
    end
  end
end
