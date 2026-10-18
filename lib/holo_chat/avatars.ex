defmodule HoloChat.Avatars do
  @moduledoc """
  Images stored in the database: avatars for people and personas, and
  scene images for role-play rooms.

  Uploads (PNG, JPEG or GIF) are center-cropped to the target aspect ratio
  (a square for avatars), scaled, flattened onto white and stored as JPEG.
  An image never changes: a new upload is a new image, so callers replace
  the id they reference and delete the old one.
  """

  use Boundary, deps: [HoloChat.Repo], exports: [Avatar]

  import Ecto.Query, warn: false

  alias HoloChat.Avatars.Avatar
  alias HoloChat.Repo

  @avatar_size {256, 256}

  @doc """
  Turns an uploaded image into a JPEG of `{width, height}` (by default the
  256x256 avatar size).

  Returns `{:ok, jpeg}` or `{:error, :invalid_image}`.
  """
  def process(binary, {width, height} \\ @avatar_size) when is_binary(binary) do
    case StbImage.read_binary(binary) do
      {:ok, %StbImage{type: {:u, 8}} = image} ->
        jpeg =
          image
          |> crop_to_aspect(width, height)
          |> StbImage.resize(height, width)
          |> to_rgb_on_white()
          |> StbImage.to_binary(:jpg)

        {:ok, jpeg}

      _unsupported ->
        {:error, :invalid_image}
    end
  end

  @doc """
  Processes and stores an uploaded image at `size` (see `process/2`).
  """
  def create_avatar(binary, size \\ @avatar_size) do
    with {:ok, jpeg} <- process(binary, size) do
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

  # Takes the largest centered region with the target aspect ratio, slicing
  # rows of the raw pixel data.
  defp crop_to_aspect(%StbImage{data: data, shape: {h, w, c}} = image, width, height) do
    {crop_w, crop_h} =
      if w * height > h * width,
        do: {max(div(h * width, height), 1), h},
        else: {w, max(div(w * height, width), 1)}

    if {crop_w, crop_h} == {w, h} do
      image
    else
      {x0, y0} = {div(w - crop_w, 2), div(h - crop_h, 2)}

      cropped =
        for y <- y0..(y0 + crop_h - 1), into: <<>> do
          binary_part(data, (y * w + x0) * c, crop_w * c)
        end

      StbImage.new(cropped, {crop_h, crop_w, c})
    end
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
