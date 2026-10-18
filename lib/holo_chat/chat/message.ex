defmodule HoloChat.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :room, :string
    field :username, :string
    field :body, :string

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for user-supplied fields. The room is set by the server
  when building the struct and is never cast from params.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:username, :body])
    |> update_change(:username, &String.trim/1)
    |> update_change(:body, &String.trim/1)
    |> validate_required([:room, :username, :body])
    |> validate_length(:username, max: 32)
    |> validate_length(:body, max: 2000)
  end
end
