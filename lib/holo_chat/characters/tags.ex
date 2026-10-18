defmodule HoloChat.Characters.Tags do
  @moduledoc """
  Tags shared by characters and scenes. Matching tags are how a scene
  finds the characters that fit it, so both sides normalize them the same
  way: lowercase slugs ("Harry Potter" becomes "harry-potter").
  """

  import Ecto.Changeset

  @max_tags 10
  @max_length 30

  @doc """
  Parses a comma-separated list into at most ten unique slugs.
  """
  def parse(text) when is_binary(text) do
    text
    |> String.split(",")
    |> Enum.map(&slug/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.take(@max_tags)
  end

  @doc """
  Formats tags for an input field.
  """
  def format(tags), do: Enum.join(tags || [], ", ")

  @doc """
  Casts the virtual `tag_list` field of a changeset into `tags`.
  """
  def cast_tag_list(changeset, attrs) do
    changeset = cast(changeset, attrs, [:tag_list])

    case fetch_change(changeset, :tag_list) do
      {:ok, text} -> put_change(changeset, :tags, parse(text || ""))
      :error -> changeset
    end
  end

  defp slug(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]+/u, "-")
    |> String.trim("-")
    |> String.slice(0, @max_length)
    |> String.trim_trailing("-")
  end
end
