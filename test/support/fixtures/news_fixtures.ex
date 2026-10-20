defmodule HoloChat.NewsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `HoloChat.News` context.
  """

  # Test support may reach into any boundary.
  use Boundary, top_level?: true, check: [in: false, out: false]

  alias HoloChat.News

  @doc "A draft by the scope's user, who must be a news editor."
  def post_fixture(scope, attrs \\ %{}) do
    {:ok, post} =
      News.create_post(scope, Enum.into(attrs, %{"title" => "A Post", "body" => "Some news."}))

    post
  end

  @doc "A post published at `now`."
  def published_post_fixture(scope, attrs \\ %{}, now \\ DateTime.utc_now()) do
    {:ok, post} = News.publish_post(scope, post_fixture(scope, attrs), now)
    post
  end
end
