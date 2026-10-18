defmodule HoloChat.Assistant do
  @moduledoc """
  The AI assistant: its admin-managed settings and the connection to the
  language model server. The assistant itself runs as
  `HoloChat.Assistant.Server`, idling in the lobby.
  """

  use Boundary,
    deps: [HoloChat.Repo, HoloChat.Accounts, HoloChat.Chat],
    exports: [Settings, LLM, Server]

  alias HoloChat.Accounts
  alias HoloChat.Assistant.{LLM, Settings}
  alias HoloChat.Repo

  @pubsub HoloChat.PubSub
  @topic "assistant"
  @settings_id 1

  @doc """
  Subscribes to assistant events: `{:assistant_settings_changed, %Settings{}}`
  and `{:assistant_status, status}` (see `HoloChat.Assistant.Server`).
  """
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc false
  def broadcast(event), do: Phoenix.PubSub.broadcast(@pubsub, @topic, event)

  @doc """
  Returns the current settings, or the defaults if none were saved yet.
  """
  def get_settings do
    Repo.get(Settings, @settings_id) || %Settings{id: @settings_id}
  end

  @doc """
  Returns a changeset for editing the settings in a form.
  """
  def change_settings(%Settings{} = settings, attrs \\ %{}) do
    Settings.changeset(settings, attrs)
  end

  @doc """
  Saves the settings (admins only) and notifies subscribers.
  """
  def update_settings(scope, attrs) do
    with :ok <- authorize(scope),
         {:ok, settings} <-
           get_settings()
           |> Settings.changeset(attrs)
           |> Repo.insert_or_update() do
      broadcast({:assistant_settings_changed, settings})
      {:ok, settings}
    end
  end

  @doc """
  Checks that a model server answers at `endpoint_url` (admins only).

  Returns `{:ok, info}` with the first model it serves as `:model` and the
  server details it reports (see `HoloChat.Assistant.LLM.server_info/1`),
  each of which may be nil.
  """
  def test_connection(scope, endpoint_url) do
    with :ok <- authorize(scope),
         {:ok, %{models: [model | _]} = info} <- LLM.impl().server_info(endpoint_url) do
      {:ok, info |> Map.delete(:models) |> Map.put(:model, model)}
    else
      {:ok, %{models: []}} -> {:error, :no_models}
      error -> error
    end
  end

  # Rough upper bound for one message: the longest allowed body at ~4
  # characters per token, plus the "username: " prefix.
  @max_message_tokens 510

  @doc """
  Returns true if, in the worst case, the prompt (system prompt plus a full
  context of maximum-length messages) and the reply fit into a model
  context window of `context_length` tokens. Unknown windows are assumed to fit.
  """
  def context_fits?(_settings, nil), do: true

  def context_fits?(%Settings{} = settings, context_length) do
    system_tokens = div(String.length(settings.system_prompt), 4)

    worst_case =
      system_tokens + settings.context_messages * @max_message_tokens + settings.max_tokens

    worst_case <= context_length
  end

  @doc """
  Returns true if `body` addresses the assistant as `@name` (any case).
  """
  def mentioned?(name, body) do
    # Not inside a word or an e-mail address, and not a longer name.
    Regex.match?(~r/(?<![\w@.])@#{Regex.escape(name)}(?!\w)/iu, body)
  end

  @doc """
  Builds the chat completion messages: the system prompt, then the room's
  recent `history` (oldest first). People's messages carry their username.
  """
  def build_prompt(%Settings{} = settings, history) do
    system = String.replace(settings.system_prompt, "{name}", settings.name)

    [
      %{role: "system", content: system}
      | Enum.map(history, fn
          %{from_assistant: true, body: body} -> %{role: "assistant", content: body}
          %{username: username, body: body} -> %{role: "user", content: "#{username}: #{body}"}
        end)
    ]
  end

  @doc """
  Turns raw model output into a chat message: drops `<think>` reasoning
  (including an unfinished block) and a leading "Name:" the model may add.
  Returns nil if nothing is left to say.
  """
  def clean_reply(name, text) do
    text
    |> String.replace(~r/<think>.*?<\/think>/s, "")
    |> String.replace(~r/<think>.*\z/s, "")
    |> String.trim()
    |> String.replace(~r/\A#{Regex.escape(name)}:\s*/i, "")
    |> String.trim()
    |> case do
      "" -> nil
      reply -> reply
    end
  end

  defp authorize(scope) do
    if Accounts.admin?(scope), do: :ok, else: {:error, :unauthorized}
  end
end
