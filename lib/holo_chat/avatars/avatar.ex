defmodule HoloChat.Avatars.Avatar do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "avatars" do
    field :content_type, :string
    field :data, :binary, redact: true

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
