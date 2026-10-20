defmodule HoloChat.Repo.Migrations.CreateRoomTopics do
  use Ecto.Migration

  # Keyed by room name, so every room can have a topic: the lobby and chat
  # rooms without a record too.
  def change do
    create table(:room_topics, primary_key: false) do
      add :room, :string, primary_key: true
      add :topic, :string, null: false

      timestamps(type: :utc_datetime)
    end
  end
end
