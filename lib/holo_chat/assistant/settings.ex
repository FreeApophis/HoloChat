defmodule HoloChat.Assistant.Settings do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # The connection shared by all personas.
  schema "assistant_settings" do
    field :enabled, :boolean, default: false
    field :endpoint_url, :string, default: "http://localhost:5001"
    # Replies generated at once, in different rooms; match the model server.
    field :parallel_replies, :integer, default: 1

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :endpoint_url, :parallel_replies])
    |> update_change(:endpoint_url, &(&1 |> String.trim() |> String.trim_trailing("/")))
    |> validate_required([:enabled, :endpoint_url, :parallel_replies])
    |> validate_number(:parallel_replies, greater_than_or_equal_to: 1, less_than_or_equal_to: 16)
    |> validate_change(:endpoint_url, &validate_url/2)
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
