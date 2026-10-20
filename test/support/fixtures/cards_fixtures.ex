defmodule HoloChat.CardsFixtures do
  @moduledoc """
  SillyTavern character cards for import tests.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  import HoloChat.AvatarFixtures

  @doc """
  A card in the V2 format: `fields` (string keys) go into `data`.
  """
  def card_v2(fields \\ %{}) do
    %{
      "spec" => "chara_card_v2",
      "spec_version" => "2.0",
      "data" => Enum.into(fields, %{"name" => "Someone"})
    }
  end

  @doc """
  A PNG image with each `{keyword, card}` pair embedded as a base64 JSON
  `tEXt` chunk, the way SillyTavern exports cards (keywords `chara` and
  `ccv3`).
  """
  def card_png(chunks, image \\ image_binary(8, 12, {30, 120, 200})) do
    # The signature, then the IHDR chunk (length, type, data, CRC).
    <<_signature::binary-8, ihdr_length::32, _rest::binary>> = image
    ihdr_size = 4 + 4 + ihdr_length + 4
    <<signature::binary-8, ihdr::binary-size(^ihdr_size), after_ihdr::binary>> = image

    text =
      for {keyword, card} <- chunks, into: <<>> do
        chunk("tEXt", keyword <> <<0>> <> Base.encode64(Jason.encode!(card)))
      end

    signature <> ihdr <> text <> after_ihdr
  end

  defp chunk(type, data) do
    <<byte_size(data)::32, type::binary, data::binary, :erlang.crc32(type <> data)::32>>
  end
end
