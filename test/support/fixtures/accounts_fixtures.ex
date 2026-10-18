defmodule HoloChat.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `HoloChat.Accounts` context.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  import Ecto.Query

  alias HoloChat.Accounts
  alias HoloChat.Accounts.Scope

  def unique_username, do: "user#{System.unique_integer([:positive])}"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      username: unique_username(),
      password: valid_user_password()
    })
  end

  def user_with_recovery_codes_fixture(attrs \\ %{}) do
    {:ok, {user, codes}} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    {user, codes}
  end

  def user_fixture(attrs \\ %{}) do
    {user, _codes} = user_with_recovery_codes_fixture(attrs)
    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    HoloChat.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    HoloChat.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
