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

  Returns `{:ok, model_id}` with the first model it serves.
  """
  def test_connection(scope, endpoint_url) do
    with :ok <- authorize(scope),
         {:ok, [model | _]} <- LLM.impl().list_models(endpoint_url) do
      {:ok, model}
    else
      {:ok, []} -> {:error, :no_models}
      error -> error
    end
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
