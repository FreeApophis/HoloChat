defmodule HoloChatWeb.Markdown do
  @moduledoc """
  Renders user-written Markdown (messages, scenarios, profiles) to safe HTML.

  The parser only produces an AST; we render it ourselves and emit nothing but
  the tags listed here, without attributes. HTML in the text is shown as text:
  every `<` is swapped for a placeholder before parsing, so the parser never
  sees a tag. Links keep only http(s) and mailto targets and open in a new tab.
  Images become links, so nobody's browser loads remote images.

  Room names written as `#room` link to the room (except inside code and
  links), navigating with LiveView, or patching with `room_links: :patch`
  where the chat itself is open. `||text||` is a spoiler, blurred until
  clicked (or focused with the keyboard).
  """

  # A private-use character the parser treats as plain text.
  @lt ""

  @tags ~w(p em strong del code pre blockquote ul ol li h1 h2 h3 h4 h5 h6
           table thead tbody tr th td)
  @void_tags ~w(br hr)
  @schemes ~w(http https mailto)
  # Text inside these is shown as typed, without room links.
  @verbatim_tags ~w(code pre)
  # A room name (see HoloChat.Chat.valid_room?/1) after # and not inside a word.
  @room_link ~r/(?<![\w#&])#([a-z0-9][a-z0-9-]{0,31})(?![\w])/u
  # ||hidden text|| within one stretch of text, revealed by a click.
  @spoiler ~r/\|\|(?=\S)(.+?)(?<=\S)\|\|/u
  @reveal_spoiler "revealed"
                  |> Phoenix.LiveView.JS.toggle_class()
                  |> Phoenix.HTML.html_escape()
                  |> Phoenix.HTML.safe_to_string()

  @doc """
  Returns the HTML for `text` as `Phoenix.HTML.safe`; empty for nil or blank text.

  Options: `room_links: :navigate` (default) or `:patch`.
  """
  def to_html(text, opts \\ [])

  def to_html(text, _opts) when text in [nil, ""], do: {:safe, ""}

  def to_html(text, opts) do
    if String.trim(text) == "" do
      {:safe, ""}
    else
      {_status, ast, _messages} =
        text
        |> String.replace("<", @lt)
        |> EarmarkParser.as_ast(breaks: true, footnotes: false, sub_sup: false)

      ctx = %{room_links: Keyword.get(opts, :room_links, :navigate), verbatim?: false}
      {:safe, render(ast, ctx)}
    end
  end

  defp render(nodes, ctx) when is_list(nodes), do: Enum.map(nodes, &render(&1, ctx))
  defp render(text, %{verbatim?: true}) when is_binary(text), do: escape(text)
  defp render(text, ctx) when is_binary(text), do: render_text(text, ctx)

  defp render({"a", attrs, children, _meta}, ctx) do
    link(attr(attrs, "href"), render(children, %{ctx | verbatim?: true}))
  end

  defp render({"img", attrs, _children, _meta}, _ctx) do
    link(attr(attrs, "src"), escape(attr(attrs, "alt") || ""))
  end

  defp render({tag, _attrs, children, _meta}, ctx) when tag in @tags do
    ctx = if tag in @verbatim_tags, do: %{ctx | verbatim?: true}, else: ctx
    ["<", tag, ">", render(children, ctx), "</", tag, ">"]
  end

  defp render({tag, _attrs, _children, _meta}, _ctx) when tag in @void_tags,
    do: ["<", tag, ">"]

  # Anything else (unknown tags) keeps only its text.
  defp render({_tag, _attrs, children, _meta}, ctx), do: render(children, ctx)

  defp render_text(text, ctx) do
    @spoiler
    |> Regex.split(text, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(@spoiler, part, capture: :all_but_first) do
        [hidden] when part == "||" <> hidden <> "||" ->
          [
            ~s(<span class="spoiler" data-role="spoiler" role="button" tabindex="0" ),
            ~s(title="Spoiler: click to show" phx-click="),
            @reveal_spoiler,
            ~s(">),
            render_room_links(hidden, ctx),
            "</span>"
          ]

        _plain ->
          render_room_links(part, ctx)
      end
    end)
  end

  defp render_room_links(text, ctx) do
    @room_link
    |> Regex.split(text, include_captures: true)
    |> Enum.map(fn part ->
      case Regex.run(@room_link, part, capture: :all_but_first) do
        [name] when part == "#" <> name -> room_link(name, ctx)
        _plain -> escape(part)
      end
    end)
  end

  # Trailing hyphens are punctuation; names need a letter ("#42" is no room).
  defp room_link(name, ctx) do
    room = String.trim_trailing(name, "-")
    rest = String.slice(name, String.length(room)..-1//1)

    if room =~ ~r/[a-z]/ do
      [
        ~s(<a href="/rooms/),
        room,
        ~s(" data-phx-link="),
        if(ctx.room_links == :patch, do: "patch", else: "redirect"),
        ~s(" data-phx-link-state="push">#),
        room,
        "</a>",
        rest
      ]
    else
      escape("#" <> name)
    end
  end

  defp link(url, content) do
    case safe_url(url) do
      nil ->
        content

      url ->
        [
          ~s(<a href="),
          escape(url),
          ~s(" target="_blank" rel="noopener noreferrer nofollow">),
          content,
          "</a>"
        ]
    end
  end

  defp safe_url(nil), do: nil

  defp safe_url(url) do
    url = String.replace(url, @lt, "<")

    case URI.parse(url) do
      %URI{scheme: scheme} when is_binary(scheme) ->
        if String.downcase(scheme) in @schemes, do: url

      _no_scheme ->
        nil
    end
  end

  defp attr(attrs, name) do
    case List.keyfind(attrs, name, 0) do
      {^name, value} -> value
      nil -> nil
    end
  end

  defp escape(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> String.replace(@lt, "&lt;")
  end
end
