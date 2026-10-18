defmodule HoloChat.Chat.Message do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :room, :string
    field :username, :string
    field :body, :string
    field :from_assistant, :boolean, default: false
    belongs_to :user, HoloChat.Accounts.User

    timestamps(type: :utc_datetime_usec)
  end

  @doc """
  Changeset for user-supplied fields. Room, author and the author's name
  are set by the server when building the struct and are never cast.
  """
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:body])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body])
    |> validate_length(:body, max: 2000)
  end
end
