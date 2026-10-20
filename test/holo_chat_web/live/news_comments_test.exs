defmodule HoloChatWeb.NewsCommentsTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.NewsFixtures

  alias HoloChat.News

  defp as(scope), do: build_conn_with_unique_ip() |> log_in_user(scope.user)

  setup do
    editor = role_scope_fixture(:news_editor)
    %{editor: editor, post: published_post_fixture(editor)}
  end

  test "readers comment, and everyone reading sees it at once", %{conn: conn, post: post} do
    reader = user_scope_fixture()
    {:ok, guest, _html} = live(conn, ~p"/news/#{post.id}")
    {:ok, view, _html} = live(as(reader), ~p"/news/#{post.id}")

    view
    |> form("#comment-form", comment: %{body: "Great *news*!"})
    |> render_submit()

    [comment] = News.list_comments(post)

    for v <- [view, guest] do
      assert has_element?(v, "#comments-#{comment.id} em", "news")
      assert has_element?(v, "#comments-#{comment.id}", reader.user.username)
    end

    # The form is cleared for the next comment.
    refute has_element?(view, "#comment-form textarea", "Great")
  end

  test "guests read comments but are asked to log in to write", %{
    conn: conn,
    post: post
  } do
    {:ok, comment} = News.create_comment(user_scope_fixture(), post, %{"body" => "First!"})

    {:ok, view, _html} = live(conn, ~p"/news/#{post.id}")

    assert has_element?(view, "#comments-#{comment.id}", "First!")
    refute has_element?(view, "#comment-form")
    assert has_element?(view, "#comment-login")
    refute has_element?(view, "#delete-comment-#{comment.id}")
  end

  test "authors delete their own comments, for everyone", %{conn: conn, post: post} do
    author = user_scope_fixture()
    {:ok, comment} = News.create_comment(author, post, %{"body" => "Oops"})
    {:ok, watcher, _html} = live(conn, ~p"/news/#{post.id}")
    {:ok, view, _html} = live(as(author), ~p"/news/#{post.id}")

    view |> element("#delete-comment-#{comment.id}") |> render_click()

    refute has_element?(view, "#comments-#{comment.id}")
    refute has_element?(watcher, "#comments-#{comment.id}")
  end

  test "moderators delete anyone's comments; other readers can't", %{post: post} do
    {:ok, comment} = News.create_comment(user_scope_fixture(), post, %{"body" => "Spam"})

    {:ok, reader_view, _html} = live(as(user_scope_fixture()), ~p"/news/#{post.id}")
    refute has_element?(reader_view, "#delete-comment-#{comment.id}")

    {:ok, view, _html} = live(as(role_scope_fixture(:moderator)), ~p"/news/#{post.id}")
    view |> element("#delete-comment-#{comment.id}") |> render_click()

    assert News.list_comments(post) == []
  end

  test "drafts take no comments", %{editor: editor} do
    draft = post_fixture(editor)

    {:ok, view, _html} = live(as(editor), ~p"/news/#{draft.id}")

    refute has_element?(view, "#comment-form")
  end
end
