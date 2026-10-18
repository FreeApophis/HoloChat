defmodule HoloChat.Assistant.OpenAICompatibleClientTest do
  use ExUnit.Case, async: true

  alias HoloChat.Assistant.OpenAICompatibleClient, as: Client

  @endpoint "http://kobold.test:5001"

  describe "list_models/1" do
    test "returns the served model ids" do
      Req.Test.stub(Client, fn conn ->
        assert conn.method == "GET"
        assert conn.host == "kobold.test"
        assert conn.request_path == "/v1/models"

        Req.Test.json(conn, %{
          "object" => "list",
          "data" => [%{"id" => "gemma"}, %{"id" => "qwen"}]
        })
      end)

      assert {:ok, ["gemma", "qwen"]} = Client.list_models(@endpoint)
    end

    test "reports connection errors" do
      Req.Test.stub(Client, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, :econnrefused} = Client.list_models(@endpoint)
    end

    test "reports unexpected HTTP statuses" do
      Req.Test.stub(Client, &Plug.Conn.send_resp(&1, 503, "loading"))

      assert {:error, {:http_status, 503}} = Client.list_models(@endpoint)
    end
  end

  describe "chat/3" do
    test "posts the conversation and returns the reply" do
      Req.Test.stub(Client, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/v1/chat/completions"

        {:ok, body, conn} = Plug.Conn.read_body(conn)

        assert %{
                 "messages" => [
                   %{"role" => "system", "content" => "Be nice."},
                   %{"role" => "user", "content" => "ada: hi"}
                 ],
                 "max_tokens" => 64,
                 "temperature" => 0.5,
                 "stream" => false
               } = Jason.decode!(body)

        Req.Test.json(conn, %{
          "choices" => [
            %{"index" => 0, "message" => %{"role" => "assistant", "content" => "Hello!"}}
          ]
        })
      end)

      messages = [%{role: "system", content: "Be nice."}, %{role: "user", content: "ada: hi"}]

      assert {:ok, "Hello!"} = Client.chat(@endpoint, messages, max_tokens: 64, temperature: 0.5)
    end

    test "reports responses without a reply" do
      Req.Test.stub(Client, &Req.Test.json(&1, %{"choices" => []}))

      assert {:error, :empty_response} = Client.chat(@endpoint, [], [])
    end

    test "reports timeouts" do
      Req.Test.stub(Client, &Req.Test.transport_error(&1, :timeout))

      assert {:error, :timeout} = Client.chat(@endpoint, [], [])
    end
  end
end
