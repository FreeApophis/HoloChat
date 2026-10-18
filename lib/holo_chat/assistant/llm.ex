defmodule HoloChat.Assistant.LLM do
  @moduledoc """
  The language model server the assistant talks to.

  The adapter is chosen with `config :holo_chat, :assistant_llm, Module`;
  it defaults to `HoloChat.Assistant.OpenAICompatibleClient`.
  """

  @type message :: %{role: String.t(), content: String.t()}

  @doc "Lists the model ids served at `endpoint_url`."
  @callback list_models(endpoint_url :: String.t()) :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Generates the next assistant message for `messages`.

  Options: `:max_tokens`, `:temperature`.
  """
  @callback chat(endpoint_url :: String.t(), messages :: [message()], opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "The configured adapter."
  def impl,
    do: Application.get_env(:holo_chat, :assistant_llm, HoloChat.Assistant.OpenAICompatibleClient)
end
