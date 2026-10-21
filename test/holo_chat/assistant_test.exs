defmodule HoloChat.AssistantTest do
  use HoloChat.DataCase, async: true

  import Mox
  import HoloChat.AccountsFixtures
  import HoloChat.CharactersFixtures
  import HoloChat.ChatFixtures, only: [unique_room: 0]

  alias HoloChat.Accounts
  alias HoloChat.Assistant
  alias HoloChat.Assistant.{LLMMock, Persona, PromptTemplate, Settings}
  alias HoloChat.Characters.Character
  alias HoloChat.Chat
  alias HoloChat.Chat.Message

  setup :verify_on_exit!

  setup do
    {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
    %{admin: user_scope_fixture(admin), member: user_scope_fixture()}
  end

  describe "get_settings/0" do
    test "returns the defaults before anything was saved" do
      assert %Settings{enabled: false, endpoint_url: "http://localhost:5001"} =
               Assistant.get_settings()
    end
  end

  describe "update_settings/2" do
    test "saves the settings and tells subscribers", %{admin: admin} do
      Assistant.subscribe()

      assert {:ok, %Settings{enabled: true, endpoint_url: "http://gpu:5001"}} =
               Assistant.update_settings(admin, %{
                 "enabled" => "true",
                 "endpoint_url" => "http://gpu:5001/"
               })

      assert %Settings{enabled: true, endpoint_url: "http://gpu:5001"} = Assistant.get_settings()
      assert_receive {:assistant_settings_changed, %Settings{enabled: true}}
    end

    test "updates the single settings record", %{admin: admin} do
      {:ok, _} = Assistant.update_settings(admin, %{"endpoint_url" => "http://first:5001"})
      {:ok, _} = Assistant.update_settings(admin, %{"endpoint_url" => "http://second:5001"})

      assert Repo.aggregate(Settings, :count) == 1
      assert Assistant.get_settings().endpoint_url == "http://second:5001"
    end

    test "validates the endpoint", %{admin: admin} do
      assert {:error, changeset} =
               Assistant.update_settings(admin, %{"endpoint_url" => "ftp://example.com"})

      assert "must be an http:// or https:// URL" in errors_on(changeset).endpoint_url
    end

    test "is only allowed for admins", %{member: member} do
      assert {:error, :unauthorized} = Assistant.update_settings(member, %{"enabled" => "true"})
      assert {:error, :unauthorized} = Assistant.update_settings(nil, %{"enabled" => "true"})
      refute Assistant.get_settings().enabled
    end
  end

  describe "create_persona/2" do
    test "creates a persona with defaults and tells subscribers", %{admin: admin} do
      Assistant.subscribe()

      assert {:ok, %Persona{} = persona} =
               Assistant.create_persona(admin, %{"name" => "Sage", "rooms" => ["help"]})

      assert persona.name == "Sage"
      assert persona.rooms == ["help"]
      assert persona.context_messages == 20
      assert persona.system_prompt =~ "{name}"
      assert_receive {:assistant_personas_changed}
    end

    test "normalizes and validates rooms", %{admin: admin} do
      {:ok, persona} =
        Assistant.create_persona(admin, %{
          "name" => "Sage",
          "rooms" => [" Help ", "lobby", "help"]
        })

      assert persona.rooms == ["help", "lobby"]

      {:error, changeset} =
        Assistant.create_persona(admin, %{"name" => "Odd", "rooms" => ["no spaces allowed"]})

      assert "contains an invalid room name: no spaces allowed" in errors_on(changeset).rooms
    end

    test "validates the persona", %{admin: admin} do
      assert {:error, changeset} =
               Assistant.create_persona(admin, %{
                 "name" => "no spaces",
                 "context_messages" => "0",
                 "max_tokens" => "100000",
                 "temperature" => "3"
               })

      errors = errors_on(changeset)
      assert "may only contain letters, digits and underscores" in errors.name
      assert errors.context_messages != []
      assert errors.max_tokens != []
      assert errors.temperature != []
    end

    test "requires unique names, ignoring case", %{admin: admin} do
      {:ok, _} = Assistant.create_persona(admin, %{"name" => "Sage"})

      assert {:error, changeset} = Assistant.create_persona(admin, %{"name" => "SAGE"})
      assert "has already been taken" in errors_on(changeset).name
    end

    test "is only allowed for admins", %{member: member} do
      assert {:error, :unauthorized} = Assistant.create_persona(member, %{"name" => "Evil"})
      assert Assistant.list_personas() == []
    end
  end

  describe "update_persona/3 and delete_persona/2" do
    setup %{admin: admin} do
      {:ok, persona} = Assistant.create_persona(admin, %{"name" => "Sage", "rooms" => ["help"]})
      Assistant.subscribe()
      %{persona: persona}
    end

    test "update changes the persona and tells subscribers", %{admin: admin, persona: persona} do
      assert {:ok, %Persona{rooms: ["help", "lobby"]}} =
               Assistant.update_persona(admin, persona, %{"rooms" => ["help", "lobby"]})

      assert_receive {:assistant_personas_changed}
    end

    test "delete removes the persona and tells subscribers", %{admin: admin, persona: persona} do
      assert {:ok, _} = Assistant.delete_persona(admin, persona)

      assert Assistant.list_personas() == []
      assert_receive {:assistant_personas_changed}
    end

    test "are only allowed for admins", %{member: member, persona: persona} do
      assert {:error, :unauthorized} = Assistant.update_persona(member, persona, %{"name" => "X"})
      assert {:error, :unauthorized} = Assistant.delete_persona(member, persona)
      assert [%Persona{name: "Sage"}] = Assistant.list_personas()
    end
  end

  describe "persona profiles" do
    import HoloChat.AvatarFixtures

    test "have a public description of up to 500 characters", %{admin: admin} do
      {:ok, persona} =
        Assistant.create_persona(admin, %{"name" => "Sage", "description" => " Reviews code. "})

      assert persona.description == "Reviews code."

      assert {:error, changeset} =
               Assistant.update_persona(admin, persona, %{
                 "description" => String.duplicate("a", 501)
               })

      assert "should be at most 500 character(s)" in errors_on(changeset).description
    end

    test "update_persona_avatar/3 replaces the avatar and deletes the old one", %{admin: admin} do
      {:ok, persona} = Assistant.create_persona(admin, %{"name" => "Sage"})
      Assistant.subscribe()

      {:ok, persona} =
        Assistant.update_persona_avatar(admin, persona, image_binary(16, 16, {1, 2, 3}))

      first = persona.avatar_id
      assert HoloChat.Avatars.get_avatar(first)
      assert_receive {:assistant_personas_changed}

      {:ok, persona} =
        Assistant.update_persona_avatar(admin, persona, image_binary(16, 16, {3, 2, 1}))

      assert persona.avatar_id != first
      assert HoloChat.Avatars.get_avatar(first) == nil
    end

    test "update_persona_avatar/3 rejects non-images and non-admins",
         %{admin: admin, member: member} do
      {:ok, persona} = Assistant.create_persona(admin, %{"name" => "Sage"})

      assert {:error, :invalid_image} = Assistant.update_persona_avatar(admin, persona, "nope")

      assert {:error, :unauthorized} =
               Assistant.update_persona_avatar(member, persona, image_binary(4, 4, {0, 0, 0}))
    end

    test "deleting a persona deletes its avatar", %{admin: admin} do
      {:ok, persona} = Assistant.create_persona(admin, %{"name" => "Sage"})

      {:ok, persona} =
        Assistant.update_persona_avatar(admin, persona, image_binary(8, 8, {5, 5, 5}))

      {:ok, _} = Assistant.delete_persona(admin, persona)

      assert HoloChat.Avatars.get_avatar(persona.avatar_id) == nil
    end
  end

  describe "prompt templates" do
    defp template_name, do: "Template #{System.unique_integer([:positive])}"

    test "admins create, update and delete them", %{admin: admin} do
      name = template_name()
      attrs = %{"name" => "  #{name} ", "body" => "Be {{char}}."}

      assert {:ok, %PromptTemplate{name: ^name} = template} =
               Assistant.create_prompt_template(admin, attrs)

      assert template in Assistant.list_prompt_templates()
      assert Assistant.get_prompt_template(template.id) == template
      assert Assistant.get_prompt_template(nil) == nil

      assert {:ok, %{body: "Be {{char}}, briefly."}} =
               Assistant.update_prompt_template(admin, template, %{
                 "body" => "Be {{char}}, briefly."
               })

      assert {:ok, _} = Assistant.delete_prompt_template(admin, template)
      assert Assistant.get_prompt_template(template.id) == nil
    end

    test "need a unique name and a body", %{admin: admin} do
      name = template_name()
      {:ok, _} = Assistant.create_prompt_template(admin, %{"name" => name, "body" => "x"})

      assert {:error, changeset} = Assistant.create_prompt_template(admin, %{"name" => name})
      assert %{body: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} =
               Assistant.create_prompt_template(admin, %{"name" => name, "body" => "y"})

      assert %{name: ["has already been taken"]} = errors_on(changeset)
    end

    test "are refused to everyone else", %{member: member} do
      assert {:error, :unauthorized} =
               Assistant.create_prompt_template(member, %{
                 "name" => template_name(),
                 "body" => "x"
               })
    end

    test "the built-in template is today's scene prompt" do
      assert Assistant.default_prompt_template() =~ "You are playing {{char}}"
      assert Assistant.default_prompt_template() =~ "{{others}}"
    end
  end

  describe "get_persona/1" do
    test "returns the persona or nil", %{admin: admin} do
      {:ok, persona} = Assistant.create_persona(admin, %{"name" => "Sage"})

      assert %Persona{name: "Sage"} = Assistant.get_persona(persona.id)
      assert Assistant.get_persona(-1) == nil
    end
  end

  describe "list_personas/0" do
    test "lists personas by name", %{admin: admin} do
      for name <- ~w(Sage Holo), do: Assistant.create_persona(admin, %{"name" => name})
      assert ["Holo", "Sage"] = Enum.map(Assistant.list_personas(), & &1.name)
    end
  end

  describe "mentioned?/2" do
    test "matches @name anywhere, ignoring case" do
      assert Assistant.mentioned?("Holo", "@Holo hi")
      assert Assistant.mentioned?("Holo", "hey @holo, what's up?")
      assert Assistant.mentioned?("Holo", "(@HOLO)")
    end

    test "ignores the bare name, other names and e-mail-like text" do
      refute Assistant.mentioned?("Holo", "Holo, hi")
      refute Assistant.mentioned?("Holo", "@Hologram hi")
      refute Assistant.mentioned?("Holo", "mail me at me@holo.dev")
    end
  end

  describe "build_prompt/2" do
    test "starts with the system prompt and maps the history to chat roles" do
      persona = %Persona{name: "Holo", system_prompt: "You are {name}."}

      history = [
        %Message{username: "ada", body: "@Holo hi", from_assistant: false},
        %Message{username: "Holo", body: "Hello ada!", from_assistant: true},
        %Message{username: "bob", body: "@Holo and me?", from_assistant: false}
      ]

      assert Assistant.build_prompt(persona, history) == [
               %{role: "system", content: "You are Holo."},
               %{role: "user", content: "ada: @Holo hi"},
               %{role: "assistant", content: "Hello ada!"},
               %{role: "user", content: "bob: @Holo and me?"}
             ]
    end

    test "writes /me actions as actions" do
      persona = %Persona{name: "Holo", system_prompt: "You are {name}."}
      history = [%Message{username: "ada", body: "/me waves at @Holo", from_assistant: false}]

      assert [_system, %{role: "user", content: "*ada waves at @Holo*"}] =
               Assistant.build_prompt(persona, history)
    end

    test "presents other personas' replies like people's messages" do
      persona = %Persona{name: "Holo", system_prompt: "You are {name}."}
      history = [%Message{username: "Sage", body: "Use a GenServer.", from_assistant: true}]

      assert [_system, %{role: "user", content: "Sage: Use a GenServer."}] =
               Assistant.build_prompt(persona, history)
    end

    test "shows players who wear a character by that character's name" do
      persona = %Persona{name: "Holo", system_prompt: "You are {name}."}
      riker = %Character{id: 7, name: "Riker"}

      history = [
        %Message{username: "ada", body: "@Holo hi", from_assistant: false, character_id: 7},
        %Message{username: "ada", body: "/me nods", from_assistant: false, character_id: 7},
        %Message{username: "Data", body: "Hm.", from_assistant: true, character_id: 9}
      ]

      assert [
               _system,
               %{role: "user", content: "Riker: @Holo hi"},
               %{role: "user", content: "*Riker nods*"},
               %{role: "user", content: "Data: Hm."}
             ] = Assistant.build_prompt(persona, history, %{7 => riker})
    end
  end

  describe "regenerate_reply/2" do
    setup %{admin: admin} do
      {:ok, _} = Assistant.update_settings(admin, %{"enabled" => "true"})
      room = unique_room()
      {:ok, holo} = Assistant.create_persona(admin, %{"name" => "Holo", "rooms" => [room]})
      luna = character_fixture(admin, %{"name" => "Luna"})
      Assistant.subscribe()
      %{room: room, holo: holo, luna: luna}
    end

    test "asks the assistant to rewrite the room's latest reply",
         %{member: member, room: room, holo: holo} do
      {:ok, reply} = Chat.create_assistant_message(room, "Holo", "Hi.", persona_id: holo.id)

      assert :ok = Assistant.regenerate_reply(member, reply.id)
      assert_receive {:regenerate_reply, %Message{id: id}}
      assert id == reply.id
    end

    test "refuses guests, older replies, people's messages and unknown ids",
         %{member: member, room: room, holo: holo, luna: luna} do
      {:ok, older} = Chat.create_character_message(room, "Luna", "Hm.", luna.id)
      {:ok, _latest} = Chat.create_assistant_message(room, "Holo", "Hi.", persona_id: holo.id)
      {:ok, people} = Chat.create_message(member, unique_room(), %{"body" => "Me."})

      assert {:error, :unauthorized} = Assistant.regenerate_reply(nil, older.id)
      assert {:error, :not_latest} = Assistant.regenerate_reply(member, older.id)
      assert {:error, :not_a_reply} = Assistant.regenerate_reply(member, people.id)
      assert {:error, :not_found} = Assistant.regenerate_reply(member, "-1")
      refute_receive {:regenerate_reply, _}
    end

    test "refuses while the assistant is off",
         %{admin: admin, member: member, room: room, holo: holo} do
      {:ok, reply} = Chat.create_assistant_message(room, "Holo", "Hi.", persona_id: holo.id)
      {:ok, _} = Assistant.update_settings(admin, %{"enabled" => "false"})

      assert {:error, :disabled} = Assistant.regenerate_reply(member, reply.id)
    end
  end

  describe "clean_reply/2" do
    test "removes reasoning blocks and surrounding whitespace" do
      assert Assistant.clean_reply("Holo", "<think>\nhmm, a greeting\n</think>\n\n Hi! ") == "Hi!"

      assert Assistant.clean_reply("Holo", "<think>a</think>Hi <think>b</think>there") ==
               "Hi there"
    end

    test "drops a leading copy of its own name" do
      assert Assistant.clean_reply("Holo", "Holo: Hi!") == "Hi!"
    end

    test "returns nil when nothing is left" do
      assert Assistant.clean_reply("Holo", "<think>only thoughts</think>") == nil
      assert Assistant.clean_reply("Holo", "<think>cut off while thinking") == nil
    end
  end

  describe "context_fits?/2" do
    test "checks the worst case (full context of maximum-size messages) against the window" do
      persona = %Persona{}

      assert Assistant.context_fits?(persona, 65_536)
      refute Assistant.context_fits?(persona, 2048)
      assert Assistant.context_fits?(%{persona | context_messages: 2, max_tokens: 256}, 2048)
    end

    test "can't tell without a known window" do
      assert Assistant.context_fits?(%Persona{}, nil)
    end
  end

  describe "test_connection/2" do
    test "reports the first model and the server details", %{admin: admin} do
      expect(LLMMock, :server_info, fn "http://kobold:5001" ->
        {:ok,
         %{
           models: ["gemma", "other"],
           server: "KoboldCpp 1.118.1",
           context_length: 65_536,
           generation_speed: 21.4
         }}
      end)

      assert {:ok,
              %{
                model: "gemma",
                server: "KoboldCpp 1.118.1",
                context_length: 65_536,
                generation_speed: 21.4
              }} = Assistant.test_connection(admin, "http://kobold:5001")
    end

    test "treats a server without models as an error", %{admin: admin} do
      expect(LLMMock, :server_info, fn _ ->
        {:ok, %{models: [], server: nil, context_length: nil, generation_speed: nil}}
      end)

      assert {:error, :no_models} = Assistant.test_connection(admin, "http://kobold:5001")
    end

    test "passes errors through", %{admin: admin} do
      expect(LLMMock, :server_info, fn _ -> {:error, :econnrefused} end)

      assert {:error, :econnrefused} = Assistant.test_connection(admin, "http://kobold:5001")
    end

    test "is only allowed for admins", %{member: member} do
      assert {:error, :unauthorized} = Assistant.test_connection(member, "http://169.254.169.254")
    end
  end
end
