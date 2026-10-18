defmodule HoloChat.Assistant.OpenAICompatibleClientTest do
  use ExUnit.Case, async: true

  alias HoloChat.Assistant.OpenAICompatibleClient, as: Client

  @endpoint "http://kobold.test:5001"

  describe "server_info/1" do
    test "combines the model list with koboldcpp's extra details" do
      Req.Test.stub(Client, fn conn ->
        assert conn.method == "GET"
        assert conn.host == "kobold.test"

        case conn.request_path do
          "/v1/models" ->
            Req.Test.json(conn, %{"data" => [%{"id" => "gemma"}, %{"id" => "qwen"}]})

          "/api/extra/version" ->
            Req.Test.json(conn, %{"result" => "KoboldCpp", "version" => "1.118.1"})

          "/api/v1/config/max_context_length" ->
            Req.Test.json(conn, %{"value" => 65_536})

          "/api/extra/perf" ->
            Req.Test.json(conn, %{"last_eval_speed" => 21.37, "total_gens" => 3})
        end
      end)

      assert {:ok,
              %{
                models: ["gemma", "qwen"],
                server: "KoboldCpp 1.118.1",
                context_length: 65_536,
                generation_speed: 21.37
              }} = Client.server_info(@endpoint)
    end

    test "leaves out details a plain OpenAI-compatible server doesn't offer" do
      Req.Test.stub(Client, fn
        %{request_path: "/v1/models"} = conn ->
          Req.Test.json(conn, %{"data" => [%{"id" => "llama"}]})

        conn ->
          Plug.Conn.send_resp(conn, 404, "not found")
      end)

      assert {:ok, %{models: ["llama"], server: nil, context_length: nil, generation_speed: nil}} =
               Client.server_info(@endpoint)
    end

    test "has no generation speed before the first generation" do
      Req.Test.stub(Client, fn
        %{request_path: "/v1/models"} = conn ->
          Req.Test.json(conn, %{"data" => [%{"id" => "gemma"}]})

        %{request_path: "/api/extra/perf"} = conn ->
          Req.Test.json(conn, %{"last_eval_speed" => 0})

        conn ->
          Plug.Conn.send_resp(conn, 404, "")
      end)

      assert {:ok, %{generation_speed: nil}} = Client.server_info(@endpoint)
    end

    test "reports connection errors" do
      Req.Test.stub(Client, &Req.Test.transport_error(&1, :econnrefused))

      assert {:error, :econnrefused} = Client.server_info(@endpoint)
    end

    test "reports unexpected HTTP statuses of the model list" do
      Req.Test.stub(Client, &Plug.Conn.send_resp(&1, 503, "loading"))

      assert {:error, {:http_status, 503}} = Client.server_info(@endpoint)
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
