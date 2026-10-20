defmodule HoloChat.AccountsTest do
  use HoloChat.DataCase, async: true

  alias HoloChat.Accounts

  import HoloChat.AccountsFixtures
  alias HoloChat.Accounts.{RecoveryCode, User, UserToken}

  describe "get_user_by_username/1" do
    test "does not return the user if the username does not exist" do
      refute Accounts.get_user_by_username("nobody")
    end

    test "returns the user, ignoring case" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_username(user.username)
      assert %User{id: ^id} = Accounts.get_user_by_username(String.upcase(user.username))
    end
  end

  describe "get_user_by_username_and_password/2" do
    test "does not return the user if the username does not exist" do
      refute Accounts.get_user_by_username_and_password("nobody", valid_user_password())
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_username_and_password(user.username, "invalid")
    end

    test "returns the user if the username and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_username_and_password(user.username, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires username and password" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{username: ["can't be blank"], password: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates the username format and length" do
      {:error, changeset} = Accounts.register_user(%{username: "no spaces!"})
      assert "may only contain letters, digits and underscores" in errors_on(changeset).username

      {:error, changeset} = Accounts.register_user(%{username: "ab"})
      assert "should be at least 3 character(s)" in errors_on(changeset).username

      {:error, changeset} = Accounts.register_user(%{username: String.duplicate("a", 21)})
      assert "should be at most 20 character(s)" in errors_on(changeset).username
    end

    test "validates the password" do
      {:error, changeset} =
        Accounts.register_user(%{
          username: unique_username(),
          password: "short",
          password_confirmation: "other"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates username uniqueness, ignoring case" do
      %{username: username} = user_fixture()

      {:error, changeset} = Accounts.register_user(valid_user_attributes(username: username))
      assert "has already been taken" in errors_on(changeset).username

      {:error, changeset} =
        Accounts.register_user(valid_user_attributes(username: String.upcase(username)))

      assert "has already been taken" in errors_on(changeset).username
    end

    test "registers the user with a hashed password and returns recovery codes" do
      username = unique_username()

      {:ok, {user, codes}} = Accounts.register_user(valid_user_attributes(username: username))

      assert user.username == username
      assert is_binary(user.hashed_password)
      assert is_nil(user.password)
      assert length(codes) == 10
      assert Enum.all?(codes, &(&1 =~ ~r/\A[A-Z2-7]{4}(-[A-Z2-7]{4}){3}\z/))
      assert Accounts.count_recovery_codes(user) == 10
    end

    test "stores recovery codes only as hashes" do
      {:ok, {user, [code | _]}} = Accounts.register_user(valid_user_attributes())

      stored = Repo.all_by(RecoveryCode, user_id: user.id)
      refute Enum.any?(stored, &(&1.hashed_code == code))
    end
  end

  describe "change_user_registration/3" do
    test "returns a changeset for username and password" do
      changeset = Accounts.change_user_registration(%User{}, %{}, validate_unique: false)
      assert changeset.required == [:password, :username]
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_password/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(
          %User{},
          %{"password" => "new valid password"},
          hash_password: false
        )

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} = Accounts.update_user_password(user, %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, {user, expired_tokens}} =
        Accounts.update_user_password(user, %{password: "new valid password"})

      assert expired_tokens == []
      assert is_nil(user.password)
      assert Accounts.get_user_by_username_and_password(user.username, "new valid password")
    end

    test "deletes all tokens but keeps recovery codes", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, {_, _}} = Accounts.update_user_password(user, %{password: "new valid password"})

      refute Repo.get_by(UserToken, user_id: user.id)
      assert Accounts.count_recovery_codes(user) == 10
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "generate_login_token/1 and login_user_by_login_token/1" do
    setup do
      user = user_fixture()
      %{user: user, token: Accounts.generate_login_token(user)}
    end

    test "stores only the hash of the token", %{token: token} do
      {:ok, raw} = Base.url_decode64(token, padding: false)

      assert %UserToken{context: "login"} =
               Repo.get_by(UserToken, token: :crypto.hash(:sha256, raw))

      refute Repo.get_by(UserToken, token: raw)
    end

    test "logs the user in exactly once", %{user: user, token: token} do
      assert {:ok, %User{id: id}} = Accounts.login_user_by_login_token(token)
      assert id == user.id
      assert {:error, :not_found} = Accounts.login_user_by_login_token(token)
    end

    test "rejects invalid tokens" do
      assert {:error, :not_found} = Accounts.login_user_by_login_token("oops")
    end

    test "rejects expired tokens", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert {:error, :not_found} = Accounts.login_user_by_login_token(token)
    end
  end

  describe "recover_user/3" do
    setup do
      {user, codes} = user_with_recovery_codes_fixture()
      %{user: user, codes: codes}
    end

    test "sets a new password with a valid code and uses the code up",
         %{user: user, codes: [code | _]} do
      _ = Accounts.generate_user_session_token(user)

      assert {:ok, {recovered, expired_tokens}} =
               Accounts.recover_user(user.username, code, %{password: "brand new password"})

      assert recovered.id == user.id
      assert [%UserToken{context: "session"}] = expired_tokens
      assert Accounts.get_user_by_username_and_password(user.username, "brand new password")
      assert Accounts.count_recovery_codes(user) == 9

      assert {:error, :invalid_recovery_code} =
               Accounts.recover_user(user.username, code, %{password: "another new password"})
    end

    test "accepts codes regardless of case, spaces and dashes", %{user: user, codes: [code | _]} do
      sloppy = code |> String.downcase() |> String.replace("-", " ")

      assert {:ok, _} =
               Accounts.recover_user(user.username, sloppy, %{password: "brand new password"})
    end

    test "rejects a wrong code", %{user: user} do
      assert {:error, :invalid_recovery_code} =
               Accounts.recover_user(user.username, "AAAA-AAAA-AAAA-AAAA", %{
                 password: "brand new password"
               })

      assert Accounts.count_recovery_codes(user) == 10
    end

    test "rejects another user's code", %{codes: [code | _]} do
      other = user_fixture()

      assert {:error, :invalid_recovery_code} =
               Accounts.recover_user(other.username, code, %{password: "brand new password"})
    end

    test "rejects an unknown username", %{codes: [code | _]} do
      assert {:error, :invalid_recovery_code} =
               Accounts.recover_user("nobody", code, %{password: "brand new password"})
    end

    test "keeps the code when the new password is invalid", %{user: user, codes: [code | _]} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Accounts.recover_user(user.username, code, %{password: "short"})

      assert "should be at least 12 character(s)" in errors_on(changeset).password
      assert Accounts.count_recovery_codes(user) == 10
    end
  end

  describe "regenerate_recovery_codes/1" do
    test "replaces all codes with ten new ones" do
      {user, old_codes} = user_with_recovery_codes_fixture()

      {:ok, _} =
        Accounts.recover_user(user.username, hd(old_codes), %{password: "brand new password"})

      assert {:ok, new_codes} = Accounts.regenerate_recovery_codes(user)
      assert length(new_codes) == 10
      assert MapSet.disjoint?(MapSet.new(new_codes), MapSet.new(old_codes))
      assert Accounts.count_recovery_codes(user) == 10

      assert {:error, :invalid_recovery_code} =
               Accounts.recover_user(user.username, Enum.at(old_codes, 1), %{
                 password: "brand new password"
               })
    end
  end

  describe "get_user_profile/1" do
    test "returns only the public profile" do
      {:ok, user} = Accounts.update_user_profile(user_fixture(), %{"description" => "Hi!"})

      assert Accounts.get_user_profile(user.id) == %{
               username: user.username,
               avatar_id: nil,
               description: "Hi!"
             }
    end

    test "returns nil for unknown users" do
      assert Accounts.get_user_profile(-1) == nil
    end
  end

  describe "update_user_profile/2" do
    test "saves a trimmed description" do
      user = user_fixture()

      assert {:ok, %User{description: "Amateur astronomer."}} =
               Accounts.update_user_profile(user, %{"description" => "  Amateur astronomer. "})
    end

    test "limits the description to 500 characters" do
      assert {:error, changeset} =
               Accounts.update_user_profile(user_fixture(), %{
                 "description" => String.duplicate("a", 501)
               })

      assert "should be at most 500 character(s)" in errors_on(changeset).description
    end

    test "only changes the description" do
      user = user_fixture()

      {:ok, updated} =
        Accounts.update_user_profile(user, %{"username" => "renamed", "is_admin" => true})

      assert updated.username == user.username
      refute updated.is_admin
    end
  end

  describe "update_user_avatar/2" do
    import HoloChat.AvatarFixtures

    test "stores the image as the user's avatar and deletes the previous one" do
      user = user_fixture()

      {:ok, user} = Accounts.update_user_avatar(user, image_binary(32, 32, {255, 0, 0}))
      first = user.avatar_id
      assert %HoloChat.Avatars.Avatar{} = HoloChat.Avatars.get_avatar(first)

      {:ok, user} = Accounts.update_user_avatar(user, image_binary(32, 32, {0, 255, 0}))
      assert user.avatar_id != first
      assert HoloChat.Avatars.get_avatar(first) == nil
      assert Accounts.get_user!(user.id).avatar_id == user.avatar_id
    end

    test "keeps the current avatar when the upload is not an image" do
      {:ok, user} = Accounts.update_user_avatar(user_fixture(), image_binary(8, 8, {1, 1, 1}))

      assert {:error, :invalid_image} = Accounts.update_user_avatar(user, "garbage")
      assert Accounts.get_user!(user.id).avatar_id == user.avatar_id
    end
  end

  describe "set_admin/2" do
    test "grants and revokes admin rights by username" do
      user = user_fixture()
      refute user.is_admin

      assert {:ok, %User{is_admin: true}} = Accounts.set_admin(String.upcase(user.username), true)
      assert Accounts.get_user!(user.id).is_admin

      assert {:ok, %User{is_admin: false}} = Accounts.set_admin(user.username, false)
    end

    test "returns an error for unknown users" do
      assert {:error, :not_found} = Accounts.set_admin("nobody", true)
    end

    test "cannot be set through registration" do
      {:ok, {user, _codes}} = Accounts.register_user(valid_user_attributes(is_admin: true))
      refute user.is_admin
    end
  end

  describe "admin?/1" do
    test "is true only for scopes of admin users" do
      user = user_fixture()
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)

      assert Accounts.admin?(user_scope_fixture(admin))
      refute Accounts.admin?(user_scope_fixture(user))
      refute Accounts.admin?(nil)
    end
  end

  describe "set_role/4" do
    setup do
      %{admin: role_scope_fixture(:admin), user: user_fixture()}
    end

    test "grants and revokes site-wide roles", %{admin: admin, user: user} do
      roles = [
        admin: :is_admin,
        moderator: :is_moderator,
        library_editor: :is_library_editor,
        news_editor: :is_news_editor
      ]

      for {role, field} <- roles do
        assert {:ok, %User{} = granted} = Accounts.set_role(admin, user.id, role, true)
        assert Map.fetch!(granted, field)
        assert {:ok, %User{} = revoked} = Accounts.set_role(admin, "#{user.id}", role, false)
        refute Map.fetch!(revoked, field)
      end
    end

    test "is only for admins", %{user: user} do
      assert {:error, :unauthorized} =
               Accounts.set_role(role_scope_fixture(:moderator), user.id, :moderator, true)

      assert {:error, :unauthorized} = Accounts.set_role(nil, user.id, :moderator, true)
    end

    test "keeps admins from revoking their own admin rights", %{admin: admin} do
      assert {:error, :own_admin} = Accounts.set_role(admin, admin.user.id, :admin, false)
      assert Accounts.get_user!(admin.user.id).is_admin
    end

    test "reports unknown users and roles", %{admin: admin, user: user} do
      assert {:error, :not_found} = Accounts.set_role(admin, -1, :moderator, true)
      assert {:error, :not_found} = Accounts.set_role(admin, user.id, :overlord, true)
    end
  end

  describe "moderator?/1, library_editor?/1 and news_editor?/1" do
    test "hold for users with the role and for admins" do
      admin = role_scope_fixture(:admin)
      moderator = role_scope_fixture(:moderator)
      editor = role_scope_fixture(:library_editor)
      user = user_scope_fixture()

      assert Accounts.moderator?(moderator)
      assert Accounts.moderator?(admin)
      refute Accounts.moderator?(editor)
      refute Accounts.moderator?(user)
      refute Accounts.moderator?(nil)

      assert Accounts.library_editor?(editor)
      assert Accounts.library_editor?(admin)
      refute Accounts.library_editor?(moderator)
      refute Accounts.library_editor?(nil)

      news_editor = role_scope_fixture(:news_editor)
      assert Accounts.news_editor?(news_editor)
      assert Accounts.news_editor?(admin)
      refute Accounts.news_editor?(editor)
      refute Accounts.news_editor?(moderator)
      refute Accounts.news_editor?(nil)

      refute Accounts.admin?(moderator)
    end
  end

  describe "search_users/2" do
    test "finds users by part of their name, for admins only" do
      admin = role_scope_fixture(:admin)
      user = user_fixture()
      part = user.username |> String.slice(2, 6) |> String.upcase()

      assert {:ok, users} = Accounts.search_users(admin, part)
      assert Enum.any?(users, &(&1.id == user.id))

      assert {:ok, users} = Accounts.search_users(admin, "")
      assert length(users) <= 50

      assert {:error, :unauthorized} = Accounts.search_users(user_scope_fixture(), part)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
