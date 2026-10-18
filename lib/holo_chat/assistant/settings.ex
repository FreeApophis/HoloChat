defmodule HoloChat.Assistant.Settings do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  # The connection shared by all personas.
  schema "assistant_settings" do
    field :enabled, :boolean, default: false
    field :endpoint_url, :string, default: "http://localhost:5001"

    timestamps(type: :utc_datetime)
  end

  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :endpoint_url])
    |> update_change(:endpoint_url, &(&1 |> String.trim() |> String.trim_trailing("/")))
    |> validate_required([:enabled, :endpoint_url])
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
