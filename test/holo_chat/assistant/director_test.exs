defmodule HoloChat.Assistant.DirectorTest do
  use ExUnit.Case, async: true

  alias HoloChat.Assistant.Director
  alias HoloChat.Characters.Character

  @luna %Character{id: 1, name: "Luna Lovegood"}
  @neville %Character{id: 2, name: "Neville Longbottom"}
  @hagrid %Character{id: 3, name: "Hagrid"}
  @cast [@luna, @neville, @hagrid]

  describe "named?/2" do
    test "matches the full or the first name, with or without @, in any case" do
      assert Director.named?(@luna, "Hello Luna Lovegood")
      assert Director.named?(@luna, "luna, come here")
      assert Director.named?(@luna, "@Luna?")
      refute Director.named?(@luna, "Lunatic behaviour")
      refute Director.named?(@luna, "Nothing to see")
    end

    test "also matches the last name, but not short name parts" do
      assert Director.named?(@luna, "Miss Lovegood?")
      refute Director.named?(%Character{id: 9, name: "Jo de Vries"}, "Do it or de-ice it")
      assert Director.named?(%Character{id: 9, name: "Jo de Vries"}, "Jo, wait")
    end
  end

  describe "responders/3" do
    test "picks the named characters, in the order they are named" do
      assert Director.responders(@cast, "Hagrid and Luna, look!", []) == [@hagrid, @luna]
    end

    test "respects the limit" do
      assert Director.responders(@cast, "Hagrid and Luna, look!", limit: 1) == [@hagrid]
    end

    test "otherwise picks one character at random, not the last speaker" do
      first = fn candidates -> hd(candidates) end

      assert Director.responders(@cast, "Hello all", random: first) == [@luna]

      assert Director.responders(@cast, "Hello all", random: first, last_speaker_id: @luna.id) ==
               [@neville]
    end

    test "a lone character may speak again" do
      assert Director.responders([@luna], "Hi", last_speaker_id: @luna.id) == [@luna]
    end

    test "with 'only when named', nobody answers unnamed messages" do
      assert Director.responders(@cast, "Hello all", policy: "mention") == []
      assert Director.responders(@cast, "Hello Hagrid", policy: "mention") == [@hagrid]
    end

    test "an empty cast never answers" do
      assert Director.responders([], "Hello", []) == []
    end
  end

  describe "next_in_chain/3" do
    test "is the first other character named in a reply" do
      assert Director.next_in_chain(@cast, @luna, "Neville, Hagrid, look!") == @neville
      assert Director.next_in_chain(@cast, @luna, "I, Luna, see nothing.") == nil
    end
  end
end
