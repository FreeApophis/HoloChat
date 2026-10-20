defmodule HoloChatWeb.NewsLiveTest do
  use HoloChatWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.NewsFixtures

  alias HoloChat.News

  describe "reading news" do
    test "lists published posts, newest first, and hides drafts", %{conn: conn} do
      editor = role_scope_fixture(:news_editor)
      older = published_post_fixture(editor, %{"title" => "Older"}, ~U[2026-10-01 10:00:00Z])
      newer = published_post_fixture(editor, %{"title" => "Newer"}, ~U[2026-10-02 10:00:00Z])
      draft = post_fixture(editor, %{"title" => "Secret"})

      {:ok, view, _html} = live(conn, ~p"/news")

      assert has_element?(view, "#post-#{older.id}", "Older")
      assert has_element?(view, "#post-#{newer.id}", "Newer")
      refute has_element?(view, "#post-#{draft.id}")
      refute has_element?(view, "#new-post")

      # Other tests publish posts too: compare only the order of our own.
      ids =
        view
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("#published-posts > article")
        |> LazyHTML.attribute("id")

      assert Enum.filter(ids, &(&1 in ["post-#{older.id}", "post-#{newer.id}"])) ==
               ["post-#{newer.id}", "post-#{older.id}"]
    end

    test "shows a published post to guests, with its Markdown", %{conn: conn} do
      editor = role_scope_fixture(:news_editor)
      post = published_post_fixture(editor, %{"title" => "Hello", "body" => "Some **bold** news"})

      {:ok, view, _html} = live(conn, ~p"/news/#{post.id}")

      assert has_element?(view, "#post-title", "Hello")
      assert has_element?(view, "#post-body strong", "bold")
      assert has_element?(view, "#post-author", editor.user.username)
      refute has_element?(view, "#edit-post")
    end

    test "keeps drafts away from other readers", %{conn: conn} do
      draft = post_fixture(role_scope_fixture(:news_editor))

      assert {:error, {:redirect, %{to: "/news"}}} = live(conn, ~p"/news/#{draft.id}")

      conn = log_in_user(conn, user_fixture())
      assert {:error, {:redirect, %{to: "/news"}}} = live(conn, ~p"/news/#{draft.id}")
    end

    test "is linked from the header", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/")

      assert {:error, {:live_redirect, %{to: "/news"}}} =
               view |> element("#news-nav-link") |> render_click()
    end

    test "lets only news editors write", %{conn: conn} do
      conn = log_in_user(conn, user_fixture())

      assert {:error, {:redirect, %{to: "/news"}}} = live(conn, ~p"/news/new")
    end
  end

  describe "as a news editor" do
    setup %{conn: conn} do
      editor = role_scope_fixture(:news_editor)
      %{conn: log_in_user(conn, editor.user), editor: editor}
    end

    test "writes a draft with a cover image, then publishes it", %{conn: conn, editor: editor} do
      {:ok, index, _html} = live(conn, ~p"/news")

      assert {:error, {:live_redirect, %{to: "/news/new"}}} =
               index |> element("#new-post") |> render_click()

      {:ok, view, _html} = live(conn, ~p"/news/new")

      assert view
             |> file_input("#post-form", :cover_image, [
               %{name: "cover.png", content: image_binary(64, 36, {9, 9, 9}), type: "image/png"}
             ])
             |> render_upload("cover.png")

      assert {:error, {:live_redirect, %{to: "/news/" <> id}}} =
               view
               |> form("#post-form", post: %{title: "Launch day", body: "We are *live*."})
               |> render_submit()

      post = News.get_post(editor, id)
      assert %{title: "Launch day", published_at: nil, author_id: author_id} = post
      assert author_id == editor.user.id
      assert post.cover_image_id

      {:ok, show, _html} = live(conn, ~p"/news/#{post.id}")
      assert has_element?(show, "#draft-badge")
      assert has_element?(show, "#post-cover[src='/avatars/#{post.cover_image_id}']")

      {:ok, index, _html} = live(conn, ~p"/news")
      assert has_element?(index, "#drafts #draft-#{post.id}")

      show |> element("#publish-post") |> render_click()
      refute has_element?(show, "#draft-badge")
      assert News.get_post(editor, post.id).published_at

      {:ok, guest_view, _html} = live(build_conn_with_unique_ip(), ~p"/news")
      assert has_element?(guest_view, "#post-#{post.id}", "Launch day")
    end

    test "edits, unpublishes and deletes a post", %{conn: conn, editor: editor} do
      post = published_post_fixture(editor, %{"title" => "Typo"})

      {:ok, form, _html} = live(conn, ~p"/news/#{post.id}/edit")

      assert {:error, {:live_redirect, %{to: path}}} =
               form |> form("#post-form", post: %{title: "Fixed"}) |> render_submit()

      assert path == "/news/#{post.id}"

      {:ok, show, _html} = live(conn, ~p"/news/#{post.id}")
      assert has_element?(show, "#post-title", "Fixed")

      show |> element("#unpublish-post") |> render_click()
      assert has_element?(show, "#draft-badge")

      assert {:error, {:live_redirect, %{to: "/news"}}} =
               show |> element("#delete-post") |> render_click()

      refute News.get_post(editor, post.id)
    end

    test "shows validation errors", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/news/new")

      html = view |> form("#post-form", post: %{title: ""}) |> render_submit()

      assert html =~ "can&#39;t be blank"
    end
  end
end
