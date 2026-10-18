defmodule HoloChat.Assistant.OpenAICompatibleClient do
  @moduledoc """
  `HoloChat.Assistant.LLM` adapter for servers that speak the OpenAI chat API
  (`/v1/models`, `/v1/chat/completions`), such as koboldcpp, llama.cpp or Ollama.

  Extra `Req` options can be configured, e.g. for tests:

      config :holo_chat, HoloChat.Assistant.OpenAICompatibleClient,
        req_options: [plug: {Req.Test, HoloChat.Assistant.OpenAICompatibleClient}]
  """

  @behaviour HoloChat.Assistant.LLM

  # Large local models can take minutes for a long answer.
  @receive_timeout :timer.minutes(3)

  # The details beyond the model list are koboldcpp extensions; servers
  # without them just leave those fields empty, quickly.
  @extra_timeout :timer.seconds(2)

  @impl true
  def server_info(endpoint_url) do
    with {:ok, %{"data" => models}} <- request(endpoint_url, method: :get, url: "/v1/models") do
      {:ok,
       %{
         models: for(%{"id" => id} <- models, do: id),
         server: extra(endpoint_url, "/api/extra/version", &server_name/1),
         context_length:
           extra(endpoint_url, "/api/v1/config/max_context_length", &positive(&1["value"])),
         generation_speed:
           extra(endpoint_url, "/api/extra/perf", &positive(&1["last_eval_speed"]))
       }}
    end
  end

  defp extra(endpoint_url, path, parse) do
    case request(endpoint_url, method: :get, url: path, receive_timeout: @extra_timeout) do
      {:ok, %{} = body} -> parse.(body)
      _error -> nil
    end
  end

  defp server_name(%{"result" => name, "version" => version}), do: "#{name} #{version}"
  defp server_name(_body), do: nil

  defp positive(number) when is_number(number) and number > 0, do: number
  defp positive(_value), do: nil

  @impl true
  def chat(endpoint_url, messages, opts) do
    body =
      %{messages: messages, stream: false}
      |> put_opt(:max_tokens, opts[:max_tokens])
      |> put_opt(:temperature, opts[:temperature])

    case request(endpoint_url, method: :post, url: "/v1/chat/completions", json: body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}}
      when is_binary(content) ->
        {:ok, content}

      {:ok, _other} ->
        {:error, :empty_response}

      error ->
        error
    end
  end

  defp request(endpoint_url, options) do
    [base_url: endpoint_url, receive_timeout: @receive_timeout, retry: false]
    |> Keyword.merge(options)
    |> Keyword.merge(config_req_options())
    |> Req.request()
    |> case do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Req.Response{status: status}} -> {:error, {:http_status, status}}
      {:error, %Req.TransportError{reason: reason}} -> {:error, reason}
      {:error, exception} -> {:error, Exception.message(exception)}
    end
  end

  defp put_opt(body, _key, nil), do: body
  defp put_opt(body, key, value), do: Map.put(body, key, value)

  defp config_req_options do
    :holo_chat |> Application.get_env(__MODULE__, []) |> Keyword.get(:req_options, [])
  end
end
