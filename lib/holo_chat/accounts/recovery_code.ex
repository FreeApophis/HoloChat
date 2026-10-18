defmodule HoloChat.Accounts.RecoveryCode do
  @moduledoc """
  Single-use codes that let a user set a new password without email.

  Codes carry 80 bits of randomness, shown to the user once as
  `XXXX-XXXX-XXXX-XXXX` (base32). Only their SHA-256 hash is stored;
  with that much entropy a slow password hash is not needed.
  """

  use Ecto.Schema
  import Ecto.Query

  @count 10
  @rand_size 10

  schema "users_recovery_codes" do
    field :hashed_code, :binary
    belongs_to :user, HoloChat.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Builds a fresh set of codes for `user`.

  Returns `{plaintext_codes, structs_to_insert}`.
  """
  def build_all(user) do
    codes = for _ <- 1..@count, do: generate()
    {codes, Enum.map(codes, &%__MODULE__{user_id: user.id, hashed_code: hash(&1)})}
  end

  @doc """
  Query for the unused code of `user_id` matching the user-typed `code`.
  """
  def by_user_and_code_query(user_id, code) do
    from c in __MODULE__, where: c.user_id == ^user_id and c.hashed_code == ^hash(code)
  end

  def by_user_query(user_id), do: from(c in __MODULE__, where: c.user_id == ^user_id)

  defp generate do
    @rand_size
    |> :crypto.strong_rand_bytes()
    |> Base.encode32()
    |> String.graphemes()
    |> Enum.chunk_every(4)
    |> Enum.map_join("-", &Enum.join/1)
  end

  # Users may type codes in lower case, with spaces or without dashes.
  defp hash(code) do
    normalized = code |> String.upcase() |> String.replace(~r/[^A-Z2-7]/, "")
    :crypto.hash(:sha256, normalized)
  end
end
