defmodule HoloChat.AssistantTest do
  use HoloChat.DataCase, async: true

  import Mox
  import HoloChat.AccountsFixtures

  alias HoloChat.Accounts
  alias HoloChat.Assistant
  alias HoloChat.Assistant.{LLMMock, Settings}

  setup :verify_on_exit!

  setup do
    {:ok, admin} = Accounts.set_admin(user_fixture().username, true)
    %{admin: user_scope_fixture(admin), member: user_scope_fixture()}
  end

  describe "get_settings/0" do
    test "returns the defaults before anything was saved" do
      assert %Settings{
               enabled: false,
               name: "Holo",
               endpoint_url: "http://localhost:5001",
               context_messages: 20
             } = Assistant.get_settings()
    end
  end

  describe "update_settings/2" do
    test "saves the settings and tells subscribers", %{admin: admin} do
      Assistant.subscribe()

      assert {:ok, %Settings{enabled: true, name: "Kobold"}} =
               Assistant.update_settings(admin, %{"enabled" => "true", "name" => "Kobold"})

      assert %Settings{enabled: true, name: "Kobold"} = Assistant.get_settings()
      assert_receive {:assistant_settings_changed, %Settings{name: "Kobold"}}
    end

    test "updates the single settings record", %{admin: admin} do
      {:ok, _} = Assistant.update_settings(admin, %{"name" => "First"})
      {:ok, _} = Assistant.update_settings(admin, %{"name" => "Second"})

      assert Repo.aggregate(Settings, :count) == 1
      assert Assistant.get_settings().name == "Second"
    end

    test "validates the settings", %{admin: admin} do
      assert {:error, changeset} =
               Assistant.update_settings(admin, %{
                 "name" => "no spaces",
                 "endpoint_url" => "ftp://example.com",
                 "context_messages" => "0",
                 "max_tokens" => "100000",
                 "temperature" => "3"
               })

      errors = errors_on(changeset)
      assert "may only contain letters, digits and underscores" in errors.name
      assert "must be an http:// or https:// URL" in errors.endpoint_url
      assert errors.context_messages != []
      assert errors.max_tokens != []
      assert errors.temperature != []
    end

    test "is only allowed for admins", %{member: member} do
      assert {:error, :unauthorized} = Assistant.update_settings(member, %{"name" => "Evil"})
      assert {:error, :unauthorized} = Assistant.update_settings(nil, %{"name" => "Evil"})
      assert Assistant.get_settings().name == "Holo"
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
      settings = %Settings{name: "Holo", system_prompt: "You are {name}."}

      history = [
        %HoloChat.Chat.Message{username: "ada", body: "@Holo hi", from_assistant: false},
        %HoloChat.Chat.Message{username: "Holo", body: "Hello ada!", from_assistant: true},
        %HoloChat.Chat.Message{username: "bob", body: "@Holo and me?", from_assistant: false}
      ]

      assert Assistant.build_prompt(settings, history) == [
               %{role: "system", content: "You are Holo."},
               %{role: "user", content: "ada: @Holo hi"},
               %{role: "assistant", content: "Hello ada!"},
               %{role: "user", content: "bob: @Holo and me?"}
             ]
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
      settings = %Settings{}

      assert Assistant.context_fits?(settings, 65_536)
      refute Assistant.context_fits?(settings, 2048)
      assert Assistant.context_fits?(%{settings | context_messages: 2, max_tokens: 256}, 2048)
    end

    test "can't tell without a known window" do
      assert Assistant.context_fits?(%Settings{}, nil)
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
