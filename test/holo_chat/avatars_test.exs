defmodule HoloChat.AvatarsTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AvatarFixtures

  alias HoloChat.Avatars
  alias HoloChat.Avatars.Avatar

  describe "process/1" do
    test "turns PNG, JPEG and GIF uploads into a 256x256 JPEG" do
      for upload <- [
            image_binary(40, 40, {255, 0, 0}, :png),
            image_binary(500, 400, {0, 0, 255}, :jpg),
            gif_binary()
          ] do
        assert {:ok, jpeg} = Avatars.process(upload)
        assert <<0xFF, 0xD8, _rest::binary>> = jpeg
        assert {:ok, %StbImage{shape: {256, 256, 3}}} = StbImage.read_binary(jpeg)
      end
    end

    test "crops wide images to their center" do
      # Left third red, middle third green, right third blue.
      thirds = fn {x, _y} ->
        cond do
          x < 100 -> {255, 0, 0}
          x < 200 -> {0, 255, 0}
          true -> {0, 0, 255}
        end
      end

      {:ok, jpeg} = Avatars.process(image_binary(300, 100, thirds))
      {:ok, image} = StbImage.read_binary(jpeg)

      for {x, y} <- [{5, 5}, {128, 128}, {250, 250}] do
        {r, g, b} = pixel(image, x, y)

        assert g > 200 and r < 60 and b < 60,
               "expected green at #{x},#{y}, got #{inspect({r, g, b})}"
      end
    end

    test "puts transparent images on a white background" do
      {:ok, jpeg} = Avatars.process(image_binary(10, 10, {0, 0, 0, 0}))
      {:ok, image} = StbImage.read_binary(jpeg)

      {r, g, b} = pixel(image, 128, 128)
      assert r > 240 and g > 240 and b > 240
    end

    test "can produce other sizes, cropping to their aspect ratio" do
      # Top half red, bottom half blue: a 16:9 crop of a square keeps the middle.
      halves = fn {_x, y} -> if y < 50, do: {255, 0, 0}, else: {0, 0, 255} end

      {:ok, jpeg} = Avatars.process(image_binary(100, 100, halves), {160, 90})
      {:ok, image} = StbImage.read_binary(jpeg)

      assert image.shape == {90, 160, 3}
      assert {r, _g, b} = pixel(image, 80, 10)
      assert r > 200 and b < 60
      assert {r, _g, b} = pixel(image, 80, 80)
      assert b > 200 and r < 60
    end

    test "rejects data that isn't an image" do
      assert {:error, :invalid_image} = Avatars.process("definitely not an image")
    end
  end

  describe "create_avatar/1, get_avatar/1 and delete_avatar/1" do
    test "store the processed image under an unguessable id" do
      assert {:ok, %Avatar{id: id, content_type: "image/jpeg"}} =
               Avatars.create_avatar(image_binary(64, 64, {9, 9, 9}))

      assert {:ok, _uuid} = Ecto.UUID.cast(id)
      assert %Avatar{data: <<0xFF, 0xD8, _::binary>>} = Avatars.get_avatar(id)

      assert :ok = Avatars.delete_avatar(id)
      assert Avatars.get_avatar(id) == nil
    end

    test "get_avatar/1 returns nil for malformed ids" do
      assert Avatars.get_avatar("../etc/passwd") == nil
    end

    test "create_avatar/1 passes processing errors through" do
      assert {:error, :invalid_image} = Avatars.create_avatar("nope")
    end
  end

  defp pixel(%StbImage{data: data, shape: {_h, w, 3}}, x, y) do
    <<r, g, b>> = binary_part(data, (y * w + x) * 3, 3)
    {r, g, b}
  end
end
