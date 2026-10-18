defmodule HoloChat.Assistant.Settings do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @default_system_prompt """
  You are {name}, a friendly AI assistant in the lobby of HoloChat, a group chat.
  Messages from people are prefixed with their username. Reply in the language
  you were addressed in, keep answers short and conversational, and do not
  prefix your reply with your own name.
  """

  schema "assistant_settings" do
    field :enabled, :boolean, default: false
    field :name, :string, default: "Holo"
    field :endpoint_url, :string, default: "http://localhost:5001"
    field :system_prompt, :string, default: String.trim(@default_system_prompt)
    field :context_messages, :integer, default: 20
    field :max_tokens, :integer, default: 512
    field :temperature, :float, default: 0.7

    timestamps(type: :utc_datetime)
  end

  @fields [
    :enabled,
    :name,
    :endpoint_url,
    :system_prompt,
    :context_messages,
    :max_tokens,
    :temperature
  ]

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, @fields)
    |> update_change(:name, &String.trim/1)
    |> update_change(:endpoint_url, &(&1 |> String.trim() |> String.trim_trailing("/")))
    |> validate_required(@fields)
    |> validate_length(:name, min: 2, max: 20)
    |> validate_format(:name, ~r/\A[a-zA-Z0-9_]+\z/,
      message: "may only contain letters, digits and underscores"
    )
    |> validate_change(:endpoint_url, &validate_url/2)
    |> validate_length(:system_prompt, max: 4000)
    |> validate_number(:context_messages, greater_than_or_equal_to: 1, less_than_or_equal_to: 50)
    |> validate_number(:max_tokens, greater_than_or_equal_to: 16, less_than_or_equal_to: 4096)
    |> validate_number(:temperature, greater_than_or_equal_to: 0, less_than_or_equal_to: 2)
  end

  defp validate_url(field, url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        []

      _ ->
        [{field, "must be an http:// or https:// URL"}]
    end
  end
end
