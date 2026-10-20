defmodule HoloChat.Accounts do
  @moduledoc """
  The Accounts context: username/password users, sessions and
  email-free account recovery via single-use recovery codes.
  """

  use Boundary, deps: [HoloChat.Repo, HoloChat.Avatars], exports: [User, Scope]

  import Ecto.Query, warn: false

  alias HoloChat.Accounts.{RecoveryCode, Scope, User, UserToken}
  alias HoloChat.Avatars
  alias HoloChat.Repo

  ## Database getters

  @doc """
  Gets a user by username, ignoring case.
  """
  def get_user_by_username(username) when is_binary(username) do
    Repo.get_by(User, username: username)
  end

  @doc """
  Gets a user by username and password.

  Returns `nil` if either is wrong, taking the same time either way.
  """
  def get_user_by_username_and_password(username, password)
      when is_binary(username) and is_binary(password) do
    user = Repo.get_by(User, username: username)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user, or nil.
  """
  def get_user(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Repo.get(User, id)
      :error -> nil
    end
  end

  ## User registration

  @doc """
  Registers a user and generates their recovery codes.

  Returns `{:ok, {user, recovery_codes}}`. The plaintext codes exist only
  in this return value; show them to the user once.
  """
  def register_user(attrs) do
    Repo.transact(fn ->
      with {:ok, user} <- %User{} |> User.registration_changeset(attrs) |> Repo.insert() do
        {:ok, {user, insert_recovery_codes!(user)}}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking registration changes.

  See `HoloChat.Accounts.User.registration_changeset/3` for options.
  """
  def change_user_registration(user, attrs \\ %{}, opts \\ []) do
    User.registration_changeset(user, attrs, Keyword.put_new(opts, :hash_password, false))
  end

  ## Profile

  @doc """
  Returns the public profile of a user (`username`, `avatar_id`,
  `description`), or nil if there is no such user.
  """
  def get_user_profile(id) do
    Repo.one(
      from u in User,
        where: u.id == ^id,
        select: %{username: u.username, avatar_id: u.avatar_id, description: u.description}
    )
  end

  @doc """
  Returns a changeset for editing the user's public profile.
  """
  def change_user_profile(%User{} = user, attrs \\ %{}) do
    User.profile_changeset(user, attrs)
  end

  @doc """
  Updates the user's public profile (the description).
  """
  def update_user_profile(%User{} = user, attrs) do
    user |> User.profile_changeset(attrs) |> Repo.update()
  end

  @doc """
  Replaces the user's avatar with an uploaded image and deletes the old one.

  Returns `{:error, :invalid_image}` if the upload can't be read, leaving the
  current avatar in place.
  """
  def update_user_avatar(%User{} = user, image) when is_binary(image) do
    Repo.transact(fn ->
      with {:ok, avatar} <- Avatars.create_avatar(image),
           {:ok, updated} <- user |> Ecto.Changeset.change(avatar_id: avatar.id) |> Repo.update() do
        :ok = Avatars.delete_avatar(user.avatar_id)
        {:ok, updated}
      end
    end)
  end

  ## Roles

  # Site-wide roles. Admins grant them (and may do everything the others do);
  # moderators manage any room; library editors edit any scenario and
  # character; news editors write the news.
  @roles %{
    admin: :is_admin,
    moderator: :is_moderator,
    library_editor: :is_library_editor,
    news_editor: :is_news_editor
  }

  @doc """
  Grants (`true`) or revokes (`false`) admin rights by username. Meant for
  operators (see `mix holo_chat.admin`); admins use `set_role/4`.
  """
  def set_admin(username, admin?) when is_binary(username) and is_boolean(admin?) do
    case get_user_by_username(username) do
      nil -> {:error, :not_found}
      user -> user |> Ecto.Changeset.change(is_admin: admin?) |> Repo.update()
    end
  end

  @doc """
  Returns true if the scope belongs to an admin.
  """
  def admin?(%Scope{user: %User{is_admin: true}}), do: true
  def admin?(_scope), do: false

  @doc """
  Returns true if the scope belongs to a moderator or an admin.
  """
  def moderator?(%Scope{user: %User{is_moderator: true}}), do: true
  def moderator?(scope), do: admin?(scope)

  @doc """
  Returns true if the scope belongs to a library editor or an admin.
  """
  def library_editor?(%Scope{user: %User{is_library_editor: true}}), do: true
  def library_editor?(scope), do: admin?(scope)

  @doc """
  Returns true if the scope belongs to a news editor or an admin.
  """
  def news_editor?(%Scope{user: %User{is_news_editor: true}}), do: true
  def news_editor?(scope), do: admin?(scope)

  @doc """
  Grants (`true`) or revokes (`false`) the site-wide `role` (`:admin`,
  `:moderator`, `:library_editor` or `:news_editor`) of the user with the given id. Only
  admins may, and they cannot revoke their own admin rights.
  """
  def set_role(scope, user_id, role, granted?) when is_boolean(granted?) do
    with true <- admin?(scope) || {:error, :unauthorized},
         {:ok, field} <- Map.fetch(@roles, role) |> or_not_found(),
         %User{} = user <- get_user(user_id) || {:error, :not_found},
         :ok <- keep_own_admin(scope, user, role, granted?) do
      user |> Ecto.Changeset.change([{field, granted?}]) |> Repo.update()
    end
  end

  defp or_not_found(:error), do: {:error, :not_found}
  defp or_not_found(ok), do: ok

  defp keep_own_admin(%Scope{user: %User{id: id}}, %User{id: id}, :admin, false),
    do: {:error, :own_admin}

  defp keep_own_admin(_scope, _user, _role, _granted?), do: :ok

  @doc """
  Returns up to 50 users whose name contains `query` (ignoring case), by
  name, with their roles. Only for admins.
  """
  def search_users(scope, query) when is_binary(query) do
    if admin?(scope) do
      escaped = String.replace(String.trim(query), ["\\", "%", "_"], &("\\" <> &1))
      pattern = "%" <> escaped <> "%"

      {:ok,
       Repo.all(
         from u in User,
           where: ilike(u.username, ^pattern),
           order_by: u.username,
           limit: 50
       )}
    else
      {:error, :unauthorized}
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `HoloChat.Accounts.User.password_changeset/3` for a list of supported options.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password and expires all of the user's tokens.

  Returns `{:ok, {user, expired_tokens}}` so callers can disconnect the
  sessions belonging to the expired tokens. Recovery codes are kept.
  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Recovery codes

  @doc """
  Returns how many unused recovery codes the user has left.
  """
  def count_recovery_codes(%User{id: user_id}) do
    Repo.aggregate(RecoveryCode.by_user_query(user_id), :count)
  end

  @doc """
  Replaces all of the user's recovery codes with a fresh set.

  Returns `{:ok, recovery_codes}`; show them to the user once.
  """
  def regenerate_recovery_codes(%User{} = user) do
    Repo.transact(fn ->
      Repo.delete_all(RecoveryCode.by_user_query(user.id))
      {:ok, insert_recovery_codes!(user)}
    end)
  end

  @doc """
  Sets a new password using a recovery code instead of the old password.

  The code is used up and all of the user's tokens are expired. A wrong
  username or code both return `{:error, :invalid_recovery_code}`, so the
  result does not reveal which usernames exist. An invalid new password
  returns `{:error, changeset}` and keeps the code.
  """
  def recover_user(username, code, password_attrs)
      when is_binary(username) and is_binary(code) do
    Repo.transact(fn ->
      with %User{} = user <- get_user_by_username(username),
           %RecoveryCode{} = recovery_code <-
             Repo.one(RecoveryCode.by_user_and_code_query(user.id, code)),
           {:ok, result} <-
             user
             |> User.password_changeset(password_attrs)
             |> update_user_and_delete_all_tokens() do
        Repo.delete!(recovery_code)
        {:ok, result}
      else
        nil -> {:error, :invalid_recovery_code}
        {:error, %Ecto.Changeset{}} = error -> error
      end
    end)
  end

  defp insert_recovery_codes!(user) do
    {codes, recovery_codes} = RecoveryCode.build_all(user)
    Enum.each(recovery_codes, &Repo.insert!/1)
    codes
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## One-time login

  @doc """
  Generates a short-lived, single-use login token for `user`.

  Used to log a user in right after they registered or recovered their
  account in a LiveView, without passing their password around.
  """
  def generate_login_token(%User{} = user) do
    {encoded_token, user_token} = UserToken.build_login_token(user)
    Repo.insert!(user_token)
    encoded_token
  end

  @doc """
  Consumes a login token, returning `{:ok, user}` or `{:error, :not_found}`.
  """
  def login_user_by_login_token(token) when is_binary(token) do
    with {:ok, query} <- UserToken.verify_login_token_query(token),
         {user, user_token} <- Repo.one(query) do
      Repo.delete!(user_token)
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
