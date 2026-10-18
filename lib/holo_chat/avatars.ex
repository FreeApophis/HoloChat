defmodule HoloChat.Avatars do
  @moduledoc """
  Avatar images for people and personas.

  Uploads (PNG, JPEG or GIF) are center-cropped to a square, scaled to
  256x256, flattened onto white and stored as JPEG in the database. An
  avatar never changes: a new upload is a new avatar, so callers replace
  the id they reference and delete the old avatar.
  """

  use Boundary, deps: [HoloChat.Repo], exports: [Avatar]

  import Ecto.Query, warn: false

  alias HoloChat.Avatars.Avatar
  alias HoloChat.Repo

  @size 256

  @doc """
  Turns an uploaded image into the stored avatar format (256x256 JPEG).

  Returns `{:ok, jpeg}` or `{:error, :invalid_image}`.
  """
  def process(binary) when is_binary(binary) do
    case StbImage.read_binary(binary) do
      {:ok, %StbImage{type: {:u, 8}} = image} ->
        jpeg =
          image
          |> crop_to_square()
          |> StbImage.resize(@size, @size)
          |> to_rgb_on_white()
          |> StbImage.to_binary(:jpg)

        {:ok, jpeg}

      _unsupported ->
        {:error, :invalid_image}
    end
  end

  @doc """
  Processes and stores an uploaded image.
  """
  def create_avatar(binary) do
    with {:ok, jpeg} <- process(binary) do
      Repo.insert(%Avatar{content_type: "image/jpeg", data: jpeg})
    end
  end

  @doc """
  Gets an avatar by id; nil if it doesn't exist or the id is malformed.
  """
  def get_avatar(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Avatar, uuid)
      :error -> nil
    end
  end

  @doc """
  Deletes the avatar with `id`, if any.
  """
  def delete_avatar(nil), do: :ok

  def delete_avatar(id) do
    Repo.delete_all(from a in Avatar, where: a.id == ^id)
    :ok
  end

  # Takes the largest centered square, slicing rows of the raw pixel data.
  defp crop_to_square(%StbImage{shape: {h, w, _c}} = image) when h == w, do: image

  defp crop_to_square(%StbImage{data: data, shape: {h, w, c}}) do
    side = min(h, w)
    {x0, y0} = {div(w - side, 2), div(h - side, 2)}

    cropped =
      for y <- y0..(y0 + side - 1), into: <<>> do
        binary_part(data, (y * w + x0) * c, side * c)
      end

    StbImage.new(cropped, {side, side, c})
  end

  # JPEG has no transparency, and grayscale/alpha variants are normalized to
  # three channels so every avatar decodes the same way.
  defp to_rgb_on_white(%StbImage{data: data, shape: {h, w, c}}) do
    rgb =
      case c do
        3 ->
          data

        4 ->
          for <<r, g, b, a <- data>>,
            into: <<>>,
            do: <<on_white(r, a), on_white(g, a), on_white(b, a)>>

        2 ->
          for <<v, a <- data>>, into: <<>>, do: <<on_white(v, a), on_white(v, a), on_white(v, a)>>

        1 ->
          for <<v <- data>>, into: <<>>, do: <<v, v, v>>
      end

    StbImage.new(rgb, {h, w, 3})
  end

  defp on_white(value, alpha), do: div(value * alpha + 255 * (255 - alpha), 255)
end
