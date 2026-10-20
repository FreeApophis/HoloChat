defmodule HoloChat.CardsTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.CardsFixtures

  alias HoloChat.Accounts.Scope
  alias HoloChat.{Cards, Characters, Scenarios}

  describe "read/1" do
    test "splits a V2 card into a character and a scenario draft, without example chats" do
      image = image_binary(8, 12, {30, 120, 200})

      card =
        card_v2(%{
          "name" => "Hermione",
          "description" => "{{char}} is a witch. {{user}} is her friend.",
          "personality" => "Clever.",
          "scenario" => "{{Char}} studies in the library.",
          "first_mes" => "*{{char}} looks up.* Oh, it's you, {{user}}.",
          "mes_example" =>
            "<START>\n{{user}}: Hi\n{{char}}: Shh!\n<START>\n<USER>: Sorry\n<BOT>: Fine.",
          "tags" => ["Harry Potter", "Hogwarts"],
          "creator_notes" => "Not for the model."
        })

      assert {:ok, draft} = Cards.read(card_png([{"chara", card}], image))

      assert draft.character == %{
               "name" => "Hermione",
               "description" => "Hermione is a witch. The player is her friend.",
               "personality" => "Clever.",
               "tag_list" => "Harry Potter, Hogwarts"
             }

      assert draft.scenario == %{
               "title" => "Hermione's story",
               "description" =>
                 "Hermione studies in the library.\n\n*Hermione looks up.* Oh, it's you, the player.",
               "tag_list" => "Harry Potter, Hogwarts"
             }

      assert draft.image == card_png([{"chara", card}], image)
    end

    test "prefers the V3 chunk over the V2 one" do
      png =
        card_png([
          {"chara", card_v2(%{"name" => "Old"})},
          {"ccv3", %{"spec" => "chara_card_v3", "data" => %{"name" => "New"}}}
        ])

      assert {:ok, %{character: %{"name" => "New"}}} = Cards.read(png)
    end

    test "reads V1 cards, which have no data envelope" do
      png = card_png([{"chara", %{"name" => "Luna", "description" => "Dreamy."}}])

      assert {:ok, %{character: %{"name" => "Luna", "description" => "Dreamy."}}} =
               Cards.read(png)
    end

    test "reads cards saved as JSON, which have no image" do
      json = Jason.encode!(card_v2(%{"name" => "Luna"}))
      assert {:ok, %{character: %{"name" => "Luna"}, image: nil}} = Cards.read(json)
    end

    test "has no scenario draft when the card has no scene" do
      assert {:ok, %{scenario: nil}} = Cards.read(card_png([{"chara", card_v2()}]))
    end

    test "rejects anything that is no card" do
      assert Cards.read(image_binary(4, 4, {0, 0, 0})) == {:error, :invalid_card}
      assert Cards.read("not a card") == {:error, :invalid_card}

      assert Cards.read(Jason.encode!(%{"spec" => "chara_card_v2", "data" => %{}})) ==
               {:error, :invalid_card}

      png = card_png([{"chara", "not json"}])
      assert Cards.read(png) == {:error, :invalid_card}
    end
  end

  describe "import_card/4" do
    setup do
      %{scope: user_scope_fixture()}
    end

    test "creates the character with its avatar and a scenario casting it", %{scope: scope} do
      image = image_binary(8, 12, {30, 120, 200})

      assert {:ok, %{character: character, scenario: scenario}} =
               Cards.import_card(
                 scope,
                 %{"name" => "Hermione", "tag_list" => "hogwarts"},
                 %{"title" => "Midnight library", "tag_list" => "hogwarts"},
                 image
               )

      assert character.owner_id == scope.user.id
      assert character.avatar_id
      assert scenario.owner_id == scope.user.id
      assert scenario.tags == ["hogwarts"]
      assert [%{id: id}] = Scenarios.list_cast(scenario)
      assert id == character.id
    end

    test "imports only the character without a scenario or image", %{scope: scope} do
      assert {:ok, %{character: character, scenario: nil}} =
               Cards.import_card(scope, %{"name" => "Luna"}, nil, nil)

      assert character.avatar_id == nil
      assert Scenarios.list_scenarios_by_owner(scope.user.id) == []
    end

    test "creates nothing when the scenario is invalid", %{scope: scope} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Cards.import_card(scope, %{"name" => "Luna"}, %{"title" => ""}, nil)

      assert %{title: ["can't be blank"]} = errors_on(changeset)
      assert Characters.list_characters_by_owner(scope.user.id) == []
    end

    test "creates nothing when the image can't be read", %{scope: scope} do
      assert Cards.import_card(scope, %{"name" => "Luna"}, nil, "broken") ==
               {:error, :invalid_image}

      assert Characters.list_characters_by_owner(scope.user.id) == []
    end

    test "guests can't import" do
      assert Cards.import_card(Scope.for_user(nil), %{"name" => "Luna"}, nil, nil) ==
               {:error, :unauthorized}
    end
  end
end
