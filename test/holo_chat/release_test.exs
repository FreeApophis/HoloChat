defmodule HoloChat.ReleaseTest do
  use HoloChat.DataCase, async: true

  import ExUnit.CaptureIO
  import HoloChat.AccountsFixtures

  alias HoloChat.Accounts
  alias HoloChat.Release

  setup do
    %{user: user_fixture()}
  end

  test "grant_admin/1 makes a user an admin", %{user: user} do
    assert capture_io(fn -> Release.grant_admin(user.username) end) =~
             "#{user.username} is now an admin"

    assert Accounts.get_user!(user.id).is_admin
  end

  test "revoke_admin/1 takes admin rights away", %{user: user} do
    capture_io(fn -> Release.grant_admin(user.username) end)

    assert capture_io(fn -> Release.revoke_admin(user.username) end) =~
             "#{user.username} is no longer an admin"

    refute Accounts.get_user!(user.id).is_admin
  end

  test "grant_admin/1 fails for unknown users" do
    assert_raise RuntimeError, ~r/No user named "nobody"/, fn -> Release.grant_admin("nobody") end
  end
end
