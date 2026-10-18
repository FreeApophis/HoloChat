defmodule Mix.Tasks.HoloChat.AdminTest do
  # Mix.shell/1 is global, so this module can't run async.
  use HoloChat.DataCase, async: false

  import HoloChat.AccountsFixtures

  alias HoloChat.Accounts
  alias Mix.Tasks.HoloChat.Admin

  setup do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
    %{user: user_fixture()}
  end

  test "grants admin rights", %{user: user} do
    Admin.run(["grant", user.username])

    assert Accounts.get_user!(user.id).is_admin
    assert_received {:mix_shell, :info, [message]}
    assert message =~ "#{user.username} is now an admin"
  end

  test "revokes admin rights", %{user: user} do
    Admin.run(["grant", user.username])
    Admin.run(["revoke", user.username])

    refute Accounts.get_user!(user.id).is_admin
  end

  test "fails for unknown users" do
    assert_raise Mix.Error, ~r/No user named "nobody"/, fn -> Admin.run(["grant", "nobody"]) end
  end

  test "explains its usage on bad arguments" do
    assert_raise Mix.Error, ~r/mix holo_chat.admin grant\|revoke USERNAME/, fn ->
      Admin.run([])
    end
  end
end
