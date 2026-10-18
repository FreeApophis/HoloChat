defmodule HoloChat.Assistant.LLM do
  @moduledoc """
  The language model server the assistant talks to.

  The adapter is chosen with `config :holo_chat, :assistant_llm, Module`;
  it defaults to `HoloChat.Assistant.OpenAICompatibleClient`.
  """

  @type message :: %{role: String.t(), content: String.t()}

  @type server_info :: %{
          models: [String.t()],
          server: String.t() | nil,
          context_length: pos_integer() | nil,
          generation_speed: float() | nil
        }

  @doc """
  Describes the server at `endpoint_url`: the model ids it serves and, where
  the server reports them, its name and version, context window (tokens) and
  the speed of its last generation (tokens per second).
  """
  @callback server_info(endpoint_url :: String.t()) :: {:ok, server_info()} | {:error, term()}

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
