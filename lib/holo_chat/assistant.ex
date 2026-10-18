defmodule HoloChat.Assistant do
  @moduledoc """
  The AI assistants: the admin-managed connection to the language model
  server, and the personas that answer to `@name` in their rooms. They run
  inside `HoloChat.Assistant.Server`.
  """

  use Boundary,
    deps: [HoloChat.Repo, HoloChat.Accounts, HoloChat.Avatars, HoloChat.Chat],
    exports: [Settings, Persona, LLM, Server]

  import Ecto.Query, warn: false

  alias HoloChat.Accounts
  alias HoloChat.Assistant.{LLM, Persona, Settings}
  alias HoloChat.Avatars
  alias HoloChat.Repo

  @pubsub HoloChat.PubSub
  @topic "assistant"
  @settings_id 1

  @doc """
  Subscribes to assistant events: `{:assistant_settings_changed, %Settings{}}`,
  `{:assistant_personas_changed}` and `{:assistant_status, status}` (see
  `HoloChat.Assistant.Server`).
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

  ## Personas

  @doc """
  Returns all personas, ordered by name.
  """
  def list_personas do
    Repo.all(from p in Persona, order_by: p.name)
  end

  @doc """
  Gets a persona. Raises `Ecto.NoResultsError` if it does not exist.
  """
  def get_persona!(id), do: Repo.get!(Persona, id)

  @doc """
  Gets a persona, or nil if it does not exist.
  """
  def get_persona(id), do: Repo.get(Persona, id)

  @doc """
  Returns a changeset for editing a persona in a form.
  """
  def change_persona(%Persona{} = persona, attrs \\ %{}) do
    Persona.changeset(persona, attrs)
  end

  @doc """
  Creates a persona (admins only) and notifies subscribers.
  """
  def create_persona(scope, attrs) do
    with :ok <- authorize(scope) do
      %Persona{} |> Persona.changeset(attrs) |> Repo.insert() |> notify_personas_changed()
    end
  end

  @doc """
  Updates a persona (admins only) and notifies subscribers.
  """
  def update_persona(scope, %Persona{} = persona, attrs) do
    with :ok <- authorize(scope) do
      persona |> Persona.changeset(attrs) |> Repo.update() |> notify_personas_changed()
    end
  end

  @doc """
  Deletes a persona and its avatar (admins only) and notifies subscribers.
  """
  def delete_persona(scope, %Persona{} = persona) do
    with :ok <- authorize(scope) do
      Repo.transact(fn -> delete_persona_and_avatar(persona) end)
      |> notify_personas_changed()
    end
  end

  @doc """
  Replaces the persona's avatar with an uploaded image (admins only) and
  deletes the old one. Returns `{:error, :invalid_image}` for unreadable uploads.
  """
  def update_persona_avatar(scope, %Persona{} = persona, image) when is_binary(image) do
    with :ok <- authorize(scope) do
      Repo.transact(fn -> replace_persona_avatar(persona, image) end)
      |> notify_personas_changed()
    end
  end

  defp delete_persona_and_avatar(persona) do
    with {:ok, deleted} <- Repo.delete(persona) do
      :ok = Avatars.delete_avatar(persona.avatar_id)
      {:ok, deleted}
    end
  end

  defp replace_persona_avatar(persona, image) do
    with {:ok, avatar} <- Avatars.create_avatar(image),
         {:ok, updated} <- persona |> Ecto.Changeset.change(avatar_id: avatar.id) |> Repo.update() do
      :ok = Avatars.delete_avatar(persona.avatar_id)
      {:ok, updated}
    end
  end

  defp notify_personas_changed({:ok, _persona} = result) do
    broadcast({:assistant_personas_changed})
    result
  end

  defp notify_personas_changed(error), do: error

  ## Connection

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
  Returns true if, in the worst case, the persona's prompt (system prompt plus a full
  context of maximum-length messages) and the reply fit into a model
  context window of `context_length` tokens. Unknown windows are assumed to fit.
  """
  def context_fits?(_persona, nil), do: true

  def context_fits?(%Persona{} = persona, context_length) do
    system_tokens = div(String.length(persona.system_prompt), 4)

    worst_case =
      system_tokens + persona.context_messages * @max_message_tokens + persona.max_tokens

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
  Builds the chat completion messages for `persona`: its system prompt, then
  the room's recent `history` (oldest first). Only the persona's own replies
  are assistant turns; everyone else, including other personas, appears as
  "name: message".
  """
  def build_prompt(%Persona{name: name} = persona, history) do
    system = String.replace(persona.system_prompt, "{name}", name)

    [
      %{role: "system", content: system}
      | Enum.map(history, fn
          %{from_assistant: true, username: ^name, body: body} ->
            %{role: "assistant", content: body}

          %{username: username, body: body} ->
            %{role: "user", content: "#{username}: #{body}"}
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
