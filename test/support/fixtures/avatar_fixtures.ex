defmodule HoloChat.AvatarFixtures do
  @moduledoc """
  Image binaries for avatar tests.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  @doc """
  An image of `width` x `height` pixels encoded as `format` (`:png` or `:jpg`).
  `color` is an RGB(A) tuple, or a function of `{x, y}` returning one.
  """
  def image_binary(width, height, color, format \\ :png) do
    pixel = if is_function(color, 1), do: color, else: fn _xy -> color end
    channels = tuple_size(pixel.({0, 0}))

    pixels =
      for y <- 0..(height - 1), x <- 0..(width - 1), into: <<>> do
        pixel.({x, y}) |> Tuple.to_list() |> :binary.list_to_bin()
      end

    pixels
    |> StbImage.new({height, width, channels})
    |> StbImage.to_binary(format)
  end

  @doc "The classic 1x1 GIF; stb_image can read GIFs but not write them."
  def gif_binary do
    Base.decode64!("R0lGODlhAQABAIAAAP///wAAACH5BAEAAAAALAAAAAABAAEAAAICRAEAOw==")
  end
end
