defmodule HoloChatWeb.MarkdownTest do
  use ExUnit.Case, async: true

  alias HoloChatWeb.Markdown

  defp html(text), do: text |> Markdown.to_html() |> Phoenix.HTML.safe_to_string()

  test "renders inline formatting and keeps single line breaks" do
    assert html("*waves* **hi** `x` ~~no~~\nnext") ==
             "<p><em>waves</em> <strong>hi</strong> <code>x</code> <del>no</del><br>next</p>"
  end

  test "renders blocks" do
    assert html("# Title\n\n> quoted\n\n- a\n- b\n\n1. one\n\n```elixir\nx < y\n```\n\n---") ==
             "<h1>Title</h1><blockquote><p>quoted</p></blockquote>" <>
               "<ul><li>a</li><li>b</li></ul><ol><li>one</li></ol>" <>
               "<pre><code>x &lt; y</code></pre><hr>"
  end

  test "renders tables without inline styles" do
    assert html("| a |\n|---|\n| 1 |") ==
             "<table><thead><tr><th>a</th></tr></thead><tbody><tr><td>1</td></tr></tbody></table>"
  end

  test "shows HTML as text" do
    assert html("<script>alert(1)</script>") == "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>"

    assert html("a <b onclick=\"x\">b</b>") ==
             "<p>a &lt;b onclick=&quot;x&quot;&gt;b&lt;/b&gt;</p>"

    assert html("<!-- hidden -->") == "<p>&lt;!-- hidden --&gt;</p>"
  end

  test "keeps characters and entities as typed text" do
    assert html("Fish & chips <3") == "<p>Fish &amp; chips &lt;3</p>"
  end

  test "opens safe links in a new tab" do
    assert html("[docs](https://example.com/?a=1&b=2)") ==
             ~s(<p><a href="https://example.com/?a=1&amp;b=2" target="_blank" rel="noopener noreferrer nofollow">docs</a></p>)

    assert html("mail [me](mailto:a@example.com)") =~ ~s(href="mailto:a@example.com")
  end

  test "drops links with other schemes but keeps their text" do
    assert html("[click](javascript:alert(1))") == "<p>click</p>"
    assert html("[x](data:text/html,hi)") == "<p>x</p>"
  end

  test "turns images into links instead of loading them" do
    assert html("![a cat](https://example.com/cat.png)") ==
             ~s(<p><a href="https://example.com/cat.png" target="_blank" rel="noopener noreferrer nofollow">a cat</a></p>)

    assert html("![](javascript:x)") == "<p></p>"
  end

  describe "#room names" do
    test "link to the room with LiveView navigation" do
      assert html("join #risa-beach, now") ==
               ~s(<p>join <a href="/rooms/risa-beach" data-phx-link="redirect" data-phx-link-state="push">#risa-beach</a>, now</p>)
    end

    test "patch instead when asked (inside the chat)" do
      assert Markdown.to_html("#lobby", room_links: :patch) |> Phoenix.HTML.safe_to_string() ==
               ~s(<p><a href="/rooms/lobby" data-phx-link="patch" data-phx-link-state="push">#lobby</a></p>)
    end

    test "are only real room names, outside words, code and links" do
      for text <- ["C#sharp", "issue #42", "#Lobby", "`#lobby`", "[see](https://x.org/#top)"] do
        refute html(text) =~ "/rooms/", "#{text} should not link to a room"
      end

      assert html("```\n#lobby\n```") == "<pre><code>#lobby</code></pre>"
      assert html("#room-1-.") =~ ~s(href="/rooms/room-1")
      assert html("#2nd-floor") =~ ~s(href="/rooms/2nd-floor")
    end
  end

  describe "||spoilers||" do
    test "hide their text until clicked" do
      html = html("The butler ||did it||, really.")

      assert html =~
               ~r{^<p>The butler <span class="spoiler" data-role="spoiler" role="button" tabindex="0" title="Spoiler: click to show" phx-click="[^"]+">did it</span>, really.</p>$}

      assert html =~ "toggle_class"
    end

    test "can hold room links, and stay text inside code" do
      assert html("||meet in #lobby||") =~ ~s(<a href="/rooms/lobby")
      assert html("`||x||`") == "<p><code>||x||</code></p>"
      assert html("a || b") == "<p>a || b</p>"
      refute html("||<b>x</b>||") =~ "<b>"
    end
  end

  test "renders nothing for nil or blank text" do
    assert html(nil) == ""
    assert html("  ") == ""
  end
end
