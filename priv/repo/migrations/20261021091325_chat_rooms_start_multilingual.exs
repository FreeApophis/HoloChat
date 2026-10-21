defmodule HoloChat.Repo.Migrations.ChatRoomsStartMultilingual do
  use Ecto.Migration

  def change do
    # Chat rooms start multilingual (nil); role-play rooms get "en" from the schema.
    alter table(:rooms) do
      modify :language, :string, default: nil, from: {:string, default: "en"}
    end
  end
end
