defmodule HoloChat.NewsTest do
  use HoloChat.DataCase, async: true

  import HoloChat.AccountsFixtures
  import HoloChat.AvatarFixtures
  import HoloChat.NewsFixtures

  alias HoloChat.{Avatars, News}
  alias HoloChat.News.{Comment, Post}

  setup do
    %{editor: role_scope_fixture(:news_editor), user: user_scope_fixture()}
  end

  describe "create_post/2" do
    test "creates a draft by the editor", %{editor: editor} do
      assert {:ok, %Post{} = post} =
               News.create_post(editor, %{"title" => " Launch ", "body" => "Hi"})

      assert %{title: "Launch", body: "Hi", published_at: nil} = post
      assert post.author_id == editor.user.id
    end

    test "requires a title", %{editor: editor} do
      assert {:error, changeset} = News.create_post(editor, %{"title" => ""})
      assert "can't be blank" in errors_on(changeset).title
    end

    test "is only for news editors and admins", %{user: user} do
      assert {:error, :unauthorized} = News.create_post(user, %{"title" => "Nope"})
      assert {:error, :unauthorized} = News.create_post(nil, %{"title" => "Nope"})
      assert {:ok, _} = News.create_post(role_scope_fixture(:admin), %{"title" => "Admin news"})
    end
  end

  describe "publishing" do
    test "publish_post/3 sets the date, unpublish_post/2 makes it a draft again",
         %{editor: editor} do
      post = post_fixture(editor)

      assert {:ok, published} = News.publish_post(editor, post, ~U[2026-10-20 09:00:00Z])
      assert published.published_at == ~U[2026-10-20 09:00:00Z]

      assert {:ok, draft} = News.unpublish_post(editor, published)
      assert draft.published_at == nil
    end

    test "is only for news editors", %{editor: editor, user: user} do
      post = post_fixture(editor)
      assert {:error, :unauthorized} = News.publish_post(user, post)
      assert {:error, :unauthorized} = News.unpublish_post(user, post)
    end
  end

  describe "listing and getting" do
    test "list_published_posts/1 returns published posts, newest first, with authors",
         %{editor: editor} do
      older = published_post_fixture(editor, %{}, ~U[2026-10-01 10:00:00Z])
      newer = published_post_fixture(editor, %{}, ~U[2026-10-02 10:00:00Z])
      _draft = post_fixture(editor)

      assert [first, second] = News.list_published_posts()
      assert {first.id, second.id} == {newer.id, older.id}
      assert first.author.username == editor.user.username

      assert [only] = News.list_published_posts(1)
      assert only.id == newer.id
    end

    test "list_drafts/1 shows drafts to news editors only", %{editor: editor, user: user} do
      draft = post_fixture(editor)
      _published = published_post_fixture(editor)

      assert [%Post{id: id}] = News.list_drafts(editor)
      assert id == draft.id
      assert News.list_drafts(user) == []
    end

    test "get_post/2 returns drafts only to news editors", %{editor: editor, user: user} do
      draft = post_fixture(editor)
      published = published_post_fixture(editor)

      assert News.get_post(editor, draft.id).author.username == editor.user.username
      refute News.get_post(user, draft.id)
      refute News.get_post(nil, draft.id)
      assert News.get_post(nil, "#{published.id}").id == published.id
      refute News.get_post(nil, "nonsense")
    end
  end

  describe "comments" do
    setup %{editor: editor} do
      %{post: published_post_fixture(editor)}
    end

    test "create_comment/3 adds a comment by the user and announces it",
         %{post: post, user: user} do
      News.subscribe_comments(post)

      assert {:ok, %Comment{} = comment} =
               News.create_comment(user, post, %{"body" => " Nice! "})

      assert comment.body == "Nice!"
      assert comment.author_id == user.user.id
      assert comment.author.username == user.user.username
      assert_receive {:comment_created, %Comment{id: id}}
      assert id == comment.id
    end

    test "create_comment/3 validates and needs a user on a published post",
         %{editor: editor, post: post, user: user} do
      assert {:error, changeset} = News.create_comment(user, post, %{"body" => "  "})
      assert "can't be blank" in errors_on(changeset).body

      assert {:error, changeset} =
               News.create_comment(user, post, %{"body" => String.duplicate("a", 2001)})

      assert errors_on(changeset).body != []
      assert {:error, :unauthorized} = News.create_comment(nil, post, %{"body" => "Hi"})

      assert {:error, :not_published} =
               News.create_comment(editor, post_fixture(editor), %{"body" => "Hi"})
    end

    test "list_comments/1 returns them oldest first, with authors", %{post: post, user: user} do
      {:ok, first} = News.create_comment(user, post, %{"body" => "1"})
      {:ok, second} = News.create_comment(user, post, %{"body" => "2"})

      assert [%{id: a, author: %{}}, %{id: b}] = News.list_comments(post)
      assert {a, b} == {first.id, second.id}
    end

    test "delete_comment/2 is for the author, moderators and news editors",
         %{editor: editor, post: post, user: user} do
      {:ok, mine} = News.create_comment(user, post, %{"body" => "mine"})
      {:ok, other} = News.create_comment(user, post, %{"body" => "other"})
      {:ok, third} = News.create_comment(user, post, %{"body" => "third"})
      News.subscribe_comments(post)

      refute News.can_delete_comment?(user_scope_fixture(), mine)
      assert {:error, :unauthorized} = News.delete_comment(user_scope_fixture(), mine)
      assert {:error, :unauthorized} = News.delete_comment(nil, mine)

      assert {:ok, _} = News.delete_comment(user, mine)
      assert {:ok, _} = News.delete_comment(role_scope_fixture(:moderator), other)
      assert {:ok, _} = News.delete_comment(editor, third)
      assert News.list_comments(post) == []

      assert_receive {:comment_deleted, %Comment{id: id}}
      assert id == mine.id
    end
  end

  describe "editing" do
    test "update_post/3 changes the text", %{editor: editor, user: user} do
      post = post_fixture(editor)

      assert {:ok, %{title: "New title"}} =
               News.update_post(editor, post, %{"title" => "New title"})

      assert {:error, :unauthorized} = News.update_post(user, post, %{"title" => "Hacked"})
    end

    test "update_post_cover/3 replaces the cover image", %{editor: editor, user: user} do
      post = post_fixture(editor)

      assert {:ok, %{cover_image_id: first}} = News.update_post_cover(editor, post, gif_binary())

      assert {:ok, %{cover_image_id: second}} =
               News.update_post_cover(editor, %{post | cover_image_id: first}, gif_binary())

      assert second != first
      refute Avatars.get_avatar(first)
      assert {:error, :invalid_image} = News.update_post_cover(editor, post, "not an image")
      assert {:error, :unauthorized} = News.update_post_cover(user, post, gif_binary())
    end

    test "delete_post/2 removes the post and its cover", %{editor: editor, user: user} do
      {:ok, post} = News.update_post_cover(editor, post_fixture(editor), gif_binary())

      assert {:error, :unauthorized} = News.delete_post(user, post)
      assert {:ok, _} = News.delete_post(editor, post)
      refute News.get_post(editor, post.id)
      refute Avatars.get_avatar(post.cover_image_id)
    end
  end
end
