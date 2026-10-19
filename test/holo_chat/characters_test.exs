defmodule HoloChat.CharactersTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.CharactersFixtures

  alias HoloChat.{Accounts, Avatars, Characters}
  alias HoloChat.Characters.{Character, Tags}

  describe "Tags.parse/1" do
    test "normalizes a comma-separated list into slugs" do
      assert Tags.parse(" Harry Potter, hogwarts ,, HOGWARTS, Ravenclaw!") ==
               ["harry-potter", "hogwarts", "ravenclaw"]
    end

    test "keeps at most ten tags of up to 30 characters" do
      tags = Tags.parse(Enum.map_join(1..12, ",", &"t#{&1}"))
      assert length(tags) == 10
      assert [long] = Tags.parse(String.duplicate("a", 40))
      assert String.length(long) == 30
    end
  end

  describe "create_character/2" do
    test "creates a character owned by the scope's user" do
      scope = user_scope_fixture()

      assert {:ok, %Character{name: "Ron", tags: ["hogwarts"]} = character} =
               Characters.create_character(scope, %{"name" => "Ron", "tag_list" => "Hogwarts"})

      assert character.owner_id == scope.user.id
      assert Characters.can_edit?(scope, character)
      refute Characters.can_edit?(user_scope_fixture(), character)
      assert Characters.can_edit?(role_scope_fixture(:library_editor), character)
      refute Characters.can_edit?(role_scope_fixture(:moderator), character)
    end

    test "validates the name and refuses guests" do
      assert {:error, changeset} = Characters.create_character(user_scope_fixture(), %{})
      assert %{name: ["can't be blank"]} = errors_on(changeset)

      assert {:error, :unauthorized} = Characters.create_character(nil, %{"name" => "X"})
    end

    test "never takes the owner from params" do
      other = user_fixture()

      {:ok, character} =
        Characters.create_character(user_scope_fixture(), %{"name" => "X", "owner_id" => other.id})

      refute character.owner_id == other.id
    end
  end

  describe "listing characters" do
    test "list_characters/1 filters by tag and sorts by name" do
      scope = user_scope_fixture()
      tag = unique_tag()
      b = character_fixture(scope, %{"name" => "B", "tag_list" => tag})
      a = character_fixture(scope, %{"name" => "A", "tag_list" => tag})
      _untagged = character_fixture(scope)

      assert Enum.map(Characters.list_characters(tag: tag), & &1.id) == [a.id, b.id]
    end

    test "suggest_characters/3 ranks by shared tags and skips excluded ones" do
      scope = user_scope_fixture()
      [t1, t2] = [unique_tag(), unique_tag()]
      one = character_fixture(scope, %{"tag_list" => t1})
      both = character_fixture(scope, %{"tag_list" => "#{t1}, #{t2}"})
      excluded = character_fixture(scope, %{"tag_list" => "#{t1}, #{t2}"})
      _none = character_fixture(scope)

      assert Enum.map(Characters.suggest_characters([t1, t2], [excluded.id]), & &1.id) ==
               [both.id, one.id]

      assert Characters.suggest_characters([], []) == []
    end

    test "search_characters/3 matches names case-insensitively" do
      scope = user_scope_fixture()
      marker = unique_tag()
      luna = character_fixture(scope, %{"name" => "Luna #{marker}"})
      excluded = character_fixture(scope, %{"name" => "Luna also #{marker}"})

      assert [%{id: id}] = Characters.search_characters(String.upcase(marker), [excluded.id])
      assert id == luna.id
      assert Characters.search_characters("  ", []) == []
    end
  end

  describe "update, avatar and delete" do
    setup do
      owner = user_scope_fixture()
      %{owner: owner, character: character_fixture(owner)}
    end

    test "the owner can update", %{owner: owner, character: character} do
      assert {:ok, %Character{personality: "Brave."}} =
               Characters.update_character(owner, character, %{"personality" => "Brave."})
    end

    test "admins can update, others cannot", %{character: character} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)

      assert {:ok, _} =
               Characters.update_character(user_scope_fixture(admin), character, %{"name" => "Y"})

      assert {:error, :unauthorized} =
               Characters.update_character(user_scope_fixture(), character, %{"name" => "Z"})
    end

    test "avatars are processed and replaced", %{owner: owner, character: character} do
      {:ok, character} =
        Characters.update_character_avatar(owner, character, image_binary(8, 8, {1, 1, 1}))

      old = character.avatar_id

      {:ok, character} =
        Characters.update_character_avatar(owner, character, image_binary(8, 8, {2, 2, 2}))

      assert character.avatar_id != old
      assert Avatars.get_avatar(old) == nil
    end

    test "the owner can delete", %{owner: owner, character: character} do
      assert {:error, :unauthorized} =
               Characters.delete_character(user_scope_fixture(), character)

      assert {:ok, _} = Characters.delete_character(owner, character)
      assert Characters.get_character(character.id) == nil
    end
  end
end
