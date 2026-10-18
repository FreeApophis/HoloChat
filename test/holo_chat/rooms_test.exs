defmodule HoloChat.RoomsTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures
  import HoloChat.RoomsFixtures

  alias HoloChat.{Accounts, Avatars, Rooms}
  alias HoloChat.Rooms.Room

  describe "create_roleplay_room/2" do
    test "creates the room with the creator as its game master" do
      gm = user_scope_fixture()
      name = unique_room()

      assert {:ok, %Room{name: ^name, kind: "roleplay", title: "Keep"} = room} =
               Rooms.create_roleplay_room(gm, %{"name" => name, "title" => "Keep"})

      assert Rooms.game_master?(gm, room)
      refute Rooms.game_master?(user_scope_fixture(), room)
      assert [%{id: id}] = Rooms.list_game_masters(room)
      assert id == gm.user.id
    end

    test "requires an account" do
      assert {:error, :unauthorized} =
               Rooms.create_roleplay_room(nil, %{"name" => unique_room(), "title" => "Keep"})
    end

    test "validates name and title" do
      gm = user_scope_fixture()

      assert {:error, changeset} = Rooms.create_roleplay_room(gm, %{"name" => "Bad Name!"})
      assert %{name: [_], title: ["can't be blank"]} = errors_on(changeset)
    end

    test "refuses names that are taken by role-play or chat rooms" do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)
      chat_room = unique_room()
      message_fixture(gm, chat_room)

      for name <- [room.name, chat_room, "lobby"] do
        assert {:error, changeset} =
                 Rooms.create_roleplay_room(gm, %{"name" => name, "title" => "Again"})

        assert %{name: ["is already taken"]} = errors_on(changeset)
      end
    end
  end

  describe "listing and getting rooms" do
    test "list_roleplay_rooms/0 returns the newest first" do
      gm = user_scope_fixture()
      first = roleplay_room_fixture(gm)
      second = roleplay_room_fixture(gm)

      ids = Enum.map(Rooms.list_roleplay_rooms(), & &1.id)
      assert Enum.find_index(ids, &(&1 == second.id)) < Enum.find_index(ids, &(&1 == first.id))
    end

    test "get_room/1 finds a room by name, or nil" do
      room = roleplay_room_fixture(user_scope_fixture())

      assert %Room{id: id} = Rooms.get_room(room.name)
      assert id == room.id
      assert Rooms.get_room(unique_room()) == nil
    end
  end

  describe "update_room/3" do
    setup do
      gm = user_scope_fixture()
      %{gm: gm, room: roleplay_room_fixture(gm)}
    end

    test "lets game masters change the scene and announces it", %{gm: gm, room: room} do
      Rooms.subscribe(room.name)

      assert {:ok, %Room{topic: "Night falls.", scenario: "Fog."}} =
               Rooms.update_room(gm, room, %{"topic" => "Night falls.", "scenario" => "Fog."})

      assert_receive {:room_updated, %Room{topic: "Night falls."}}
    end

    test "never changes the name", %{gm: gm, room: room} do
      assert {:ok, %Room{name: name}} = Rooms.update_room(gm, room, %{"name" => "renamed"})
      assert name == room.name
    end

    test "lets admins manage any room", %{room: room} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
      assert {:ok, _room} = Rooms.update_room(user_scope_fixture(admin), room, %{"topic" => "x"})
    end

    test "refuses players and guests", %{room: room} do
      assert {:error, :unauthorized} =
               Rooms.update_room(user_scope_fixture(), room, %{"topic" => "x"})

      assert {:error, :unauthorized} = Rooms.update_room(nil, room, %{"topic" => "x"})
    end
  end

  describe "update_room_image/4" do
    test "stores a card and a background image and replaces old ones" do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)

      {:ok, room} = Rooms.update_room_image(gm, room, :card, image_binary(64, 36, {1, 1, 1}))
      old_card = room.card_image_id

      {:ok, room} = Rooms.update_room_image(gm, room, :card, image_binary(64, 36, {2, 2, 2}))
      {:ok, room} = Rooms.update_room_image(gm, room, :background, image_binary(9, 9, {3, 3, 3}))

      assert Avatars.get_avatar(old_card) == nil
      assert {:ok, %StbImage{shape: {360, 640, 3}}} = read_image(room.card_image_id)
      assert {:ok, %StbImage{shape: {900, 1600, 3}}} = read_image(room.background_image_id)
    end

    test "refuses players and unreadable images" do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm)

      assert {:error, :unauthorized} =
               Rooms.update_room_image(user_scope_fixture(), room, :card, gif_binary())

      assert {:error, :invalid_image} = Rooms.update_room_image(gm, room, :card, "nope")
    end
  end

  describe "game masters" do
    setup do
      gm = user_scope_fixture()
      %{gm: gm, room: roleplay_room_fixture(gm)}
    end

    test "can add and remove other game masters", %{gm: gm, room: room} do
      other = user_fixture()

      assert {:ok, _user} = Rooms.add_game_master(gm, room, other.username)
      assert {:ok, _user} = Rooms.add_game_master(gm, room, other.username)
      assert Rooms.game_master?(user_scope_fixture(other), room)
      assert length(Rooms.list_game_masters(room)) == 2

      assert :ok = Rooms.remove_game_master(gm, room, other.id)
      refute Rooms.game_master?(user_scope_fixture(other), room)
    end

    test "cannot remove the last one", %{gm: gm, room: room} do
      assert {:error, :last_game_master} = Rooms.remove_game_master(gm, room, gm.user.id)
    end

    test "reports unknown users and refuses players", %{gm: gm, room: room} do
      assert {:error, :not_found} = Rooms.add_game_master(gm, room, "nobody-#{unique_username()}")

      assert {:error, :unauthorized} =
               Rooms.add_game_master(user_scope_fixture(), room, gm.user.username)
    end
  end

  describe "tags" do
    test "scenes take a comma-separated tag list" do
      gm = user_scope_fixture()
      room = roleplay_room_fixture(gm, %{"tag_list" => "Harry Potter, Hogwarts"})
      assert room.tags == ["harry-potter", "hogwarts"]

      {:ok, room} = Rooms.update_room(gm, room, %{"tag_list" => "Discworld"})
      assert room.tags == ["discworld"]
    end
  end

  describe "the cast" do
    setup do
      gm = user_scope_fixture()
      tag = unique_tag()
      %{gm: gm, tag: tag, room: roleplay_room_fixture(gm, %{"tag_list" => tag})}
    end

    test "game masters cast and uncast library characters, announcing it",
         %{gm: gm, room: room} do
      character = character_fixture(user_scope_fixture())
      Rooms.subscribe(room.name)

      assert {:ok, _room} = Rooms.cast_character(gm, room, character.id)
      assert {:ok, _room} = Rooms.cast_character(gm, room, character.id)
      assert_receive {:room_updated, _}
      assert [%{id: id}] = Rooms.list_cast(room)
      assert id == character.id

      assert {:ok, _room} = Rooms.uncast_character(gm, room, character.id)
      assert Rooms.list_cast(room) == []
    end

    test "players cannot change the cast", %{room: room} do
      character = character_fixture(user_scope_fixture())

      assert {:error, :unauthorized} =
               Rooms.cast_character(user_scope_fixture(), room, character.id)
    end

    test "suggest_cast/1 suggests tagged characters not yet cast",
         %{gm: gm, room: room, tag: tag} do
      cast = character_fixture(gm, %{"tag_list" => tag})
      fitting = character_fixture(gm, %{"tag_list" => tag})
      {:ok, _room} = Rooms.cast_character(gm, room, cast.id)

      assert Enum.map(Rooms.suggest_cast(room), & &1.id) == [fitting.id]
    end
  end

  defp read_image(id), do: StbImage.read_binary(Avatars.get_avatar(id).data)
end
