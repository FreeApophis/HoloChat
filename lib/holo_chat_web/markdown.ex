defmodule HoloChatWeb.Markdown do
  @moduledoc """
  Renders user-written Markdown (messages, scenarios, profiles) to safe HTML.

  The parser only produces an AST; we render it ourselves and emit nothing but
  the tags listed here, without attributes. HTML in the text is shown as text:
  every `<` is swapped for a placeholder before parsing, so the parser never
  sees a tag. Links keep only http(s) and mailto targets and open in a new tab.
  Images become links, so nobody's browser loads remote images.
  """

  # A private-use character the parser treats as plain text.
  @lt ""

  @tags ~w(p em strong del code pre blockquote ul ol li h1 h2 h3 h4 h5 h6
           table thead tbody tr th td)
  @void_tags ~w(br hr)
  @schemes ~w(http https mailto)

  @doc """
  Returns the HTML for `text` as `Phoenix.HTML.safe`; empty for nil or blank text.
  """
  def to_html(text) when text in [nil, ""], do: {:safe, ""}

  def to_html(text) do
    if String.trim(text) == "" do
      {:safe, ""}
    else
      {_status, ast, _messages} =
        text
        |> String.replace("<", @lt)
        |> EarmarkParser.as_ast(breaks: true, footnotes: false, sub_sup: false)

      {:safe, render(ast)}
    end
  end

  defp render(nodes) when is_list(nodes), do: Enum.map(nodes, &render/1)
  defp render(text) when is_binary(text), do: escape(text)

  defp render({"a", attrs, children, _meta}) do
    link(attr(attrs, "href"), render(children))
  end

  defp render({"img", attrs, _children, _meta}) do
    link(attr(attrs, "src"), escape(attr(attrs, "alt") || ""))
  end

  defp render({tag, _attrs, children, _meta}) when tag in @tags,
    do: ["<", tag, ">", render(children), "</", tag, ">"]

  defp render({tag, _attrs, _children, _meta}) when tag in @void_tags, do: ["<", tag, ">"]

  # Anything else (unknown tags) keeps only its text.
  defp render({_tag, _attrs, children, _meta}), do: render(children)

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
