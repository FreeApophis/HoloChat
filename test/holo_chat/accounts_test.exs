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

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end
end
