defmodule HoloChat.ScenariosTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ScenariosFixtures

  alias HoloChat.{Accounts, Avatars, Scenarios}
  alias HoloChat.Scenarios.Scenario

  describe "create_scenario/2" do
    test "adds a scenario owned by the scope's user" do
      owner = user_scope_fixture()

      assert {:ok, %Scenario{} = scenario} =
               Scenarios.create_scenario(owner, %{
                 "title" => " Risa ",
                 "topic" => "Sun and surf.",
                 "description" => "A pleasure planet.",
                 "tag_list" => "Star Trek, Holiday"
               })

      assert %{title: "Risa", topic: "Sun and surf.", description: "A pleasure planet."} =
               scenario

      assert scenario.tags == ["star-trek", "holiday"]
      assert scenario.owner_id == owner.user.id
    end

    test "validates the fields" do
      assert {:error, changeset} =
               Scenarios.create_scenario(user_scope_fixture(), %{
                 "title" => "",
                 "topic" => String.duplicate("x", 161),
                 "description" => String.duplicate("x", 4001)
               })

      assert %{title: ["can't be blank"], topic: [_], description: [_]} = errors_on(changeset)
    end

    test "requires an account" do
      assert {:error, :unauthorized} = Scenarios.create_scenario(nil, %{"title" => "Risa"})
    end
  end

  describe "listing and getting" do
    test "list_scenarios/0 returns the newest first" do
      owner = user_scope_fixture()
      first = scenario_fixture(owner)
      second = scenario_fixture(owner)

      ids = Enum.map(Scenarios.list_scenarios(), & &1.id)
      assert Enum.find_index(ids, &(&1 == second.id)) < Enum.find_index(ids, &(&1 == first.id))
    end

    test "get_scenario/1 returns nil for unknown or malformed ids" do
      scenario = scenario_fixture(user_scope_fixture())

      assert %Scenario{id: id} = Scenarios.get_scenario(to_string(scenario.id))
      assert id == scenario.id
      assert Scenarios.get_scenario("nope") == nil
      assert Scenarios.get_scenario(-1) == nil
    end

    test "list_scenarios_by_ids/1" do
      scenario = scenario_fixture(user_scope_fixture())
      assert [%Scenario{id: id}] = Scenarios.list_scenarios_by_ids([scenario.id, -1])
      assert id == scenario.id
    end
  end

  describe "update_scenario/3" do
    setup do
      owner = user_scope_fixture()
      %{owner: owner, scenario: scenario_fixture(owner)}
    end

    test "lets the owner change it and announces the change", %{owner: owner, scenario: s} do
      Scenarios.subscribe()

      assert {:ok, %Scenario{topic: "Night falls."}} =
               Scenarios.update_scenario(owner, s, %{"topic" => "Night falls."})

      # The topic is global: match this test's scenario.
      id = s.id
      assert_receive {:scenario_updated, %Scenario{id: ^id, topic: "Night falls."}}
    end

    test "lets admins change any scenario", %{scenario: s} do
      {:ok, admin} = Accounts.set_admin(user_fixture().username, true)

      assert {:ok, _} = Scenarios.update_scenario(user_scope_fixture(admin), s, %{"topic" => "x"})
    end

    test "refuses everyone else", %{scenario: s} do
      assert {:error, :unauthorized} =
               Scenarios.update_scenario(user_scope_fixture(), s, %{"topic" => "x"})

      assert {:error, :unauthorized} = Scenarios.update_scenario(nil, s, %{"topic" => "x"})
      refute Scenarios.can_edit?(user_scope_fixture(), s)
    end

    test "library editors may edit any scenario" do
      s = scenario_fixture(user_scope_fixture())
      editor = role_scope_fixture(:library_editor)

      assert Scenarios.can_edit?(editor, s)
      assert {:ok, _} = Scenarios.update_scenario(editor, s, %{"topic" => "Edited"})
      refute Scenarios.can_edit?(role_scope_fixture(:moderator), s)
    end
  end

  describe "update_scenario_image/4" do
    test "stores a card and a background image and replaces old ones" do
      owner = user_scope_fixture()
      s = scenario_fixture(owner)

      {:ok, s} = Scenarios.update_scenario_image(owner, s, :card, image_binary(64, 36, {1, 1, 1}))
      old_card = s.card_image_id

      {:ok, s} = Scenarios.update_scenario_image(owner, s, :card, image_binary(64, 36, {2, 2, 2}))

      {:ok, s} =
        Scenarios.update_scenario_image(owner, s, :background, image_binary(9, 9, {3, 3, 3}))

      assert Avatars.get_avatar(old_card) == nil
      assert {:ok, %StbImage{shape: {360, 640, 3}}} = read_image(s.card_image_id)
      assert {:ok, %StbImage{shape: {900, 1600, 3}}} = read_image(s.background_image_id)
    end

    test "refuses others and unreadable images" do
      owner = user_scope_fixture()
      s = scenario_fixture(owner)

      assert {:error, :unauthorized} =
               Scenarios.update_scenario_image(user_scope_fixture(), s, :card, gif_binary())

      assert {:error, :invalid_image} = Scenarios.update_scenario_image(owner, s, :card, "nope")
    end
  end

  describe "the suggested cast" do
    setup do
      owner = user_scope_fixture()
      tag = unique_tag()
      %{owner: owner, tag: tag, scenario: scenario_fixture(owner, %{"tag_list" => tag})}
    end

    test "the owner casts and uncasts library characters", %{owner: owner, scenario: s} do
      character = character_fixture(user_scope_fixture())
      Scenarios.subscribe()

      assert {:ok, _} = Scenarios.cast_character(owner, s, character.id)
      assert {:ok, _} = Scenarios.cast_character(owner, s, character.id)
      id = s.id
      assert_receive {:scenario_updated, %Scenario{id: ^id}}
      assert [%{id: id}] = Scenarios.list_cast(s)
      assert id == character.id

      assert {:ok, _} = Scenarios.uncast_character(owner, s, character.id)
      assert Scenarios.list_cast(s) == []
    end

    test "others cannot change it, and unknown characters are reported",
         %{owner: owner, scenario: s} do
      character = character_fixture(owner)

      assert {:error, :unauthorized} =
               Scenarios.cast_character(user_scope_fixture(), s, character.id)

      assert {:error, :not_found} = Scenarios.cast_character(owner, s, -1)
    end

    test "suggest_cast/1 suggests tagged characters not yet cast",
         %{owner: owner, scenario: s, tag: tag} do
      cast = character_fixture(owner, %{"tag_list" => tag})
      fitting = character_fixture(owner, %{"tag_list" => tag})
      {:ok, _} = Scenarios.cast_character(owner, s, cast.id)

      assert Enum.map(Scenarios.suggest_cast(s), & &1.id) == [fitting.id]
    end
  end

  defp read_image(id), do: StbImage.read_binary(Avatars.get_avatar(id).data)
end
