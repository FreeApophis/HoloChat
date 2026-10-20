defmodule HoloChat.Characters do
  @moduledoc """
  The Characters context: a shared library of characters.

  Characters exist independently of scenes; a scene casts them (see
  `HoloChat.Rooms`). Any registered user can add characters; the owner and
  admins can change them. Tags (see `Tags`) suggest which characters fit
  which scenes.
  """

  use Boundary,
    deps: [HoloChat.Repo, HoloChat.Accounts, HoloChat.Avatars],
    exports: [Character, Tags]

  import Ecto.Query, warn: false

  alias HoloChat.{Accounts, Avatars}
  alias HoloChat.Accounts.{Scope, User}
  alias HoloChat.Characters.{Character, Tags}
  alias HoloChat.Repo

  @doc """
  Returns characters sorted by name. Pass `tag:` to only get characters
  with that tag.
  """
  def list_characters(opts \\ []) do
    Character
    |> with_tag(opts[:tag])
    |> order_by([c], asc: fragment("lower(?)", c.name), asc: c.id)
    |> Repo.all()
  end

  @doc """
  Returns the characters the user with the given id created, by name.
  """
  def list_characters_by_owner(user_id) do
    Character
    |> where([c], c.owner_id == ^user_id)
    |> order_by([c], asc: fragment("lower(?)", c.name), asc: c.id)
    |> Repo.all()
  end

  defp with_tag(query, nil), do: query
  defp with_tag(query, tag), do: where(query, [c], ^tag in c.tags)

  @doc """
  Returns up to `limit` characters sharing at least one of `tags`, the ones
  sharing the most first, leaving out `exclude_ids`.
  """
  def suggest_characters(tags, exclude_ids, limit \\ 12)
  def suggest_characters([], _exclude_ids, _limit), do: []

  def suggest_characters(tags, exclude_ids, limit) do
    Character
    |> where([c], fragment("? && ?::varchar[]", c.tags, ^tags))
    |> where([c], c.id not in ^exclude_ids)
    |> order_by([c],
      desc:
        fragment(
          "cardinality(ARRAY(SELECT unnest(?) INTERSECT SELECT unnest(?::varchar[])))",
          c.tags,
          ^tags
        ),
      asc: fragment("lower(?)", c.name),
      asc: c.id
    )
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Returns up to `limit` characters whose name contains `query`, ignoring
  case, leaving out `exclude_ids`.
  """
  def search_characters(query, exclude_ids, limit \\ 12) do
    case String.trim(query) do
      "" ->
        []

      text ->
        pattern = "%" <> String.replace(text, ~r/[\\%_]/, "\\\\\\0") <> "%"

        Character
        |> where([c], ilike(c.name, ^pattern))
        |> where([c], c.id not in ^exclude_ids)
        |> order_by([c], asc: fragment("lower(?)", c.name), asc: c.id)
        |> limit(^limit)
        |> Repo.all()
    end
  end

  @doc """
  Returns the characters with the given ids, sorted by name.
  """
  def list_characters_by_ids(ids) do
    Character
    |> where([c], c.id in ^ids)
    |> order_by([c], asc: fragment("lower(?)", c.name), asc: c.id)
    |> Repo.all()
  end

  @doc """
  Gets a character; nil if it doesn't exist or the id is malformed.
  """
  def get_character(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Repo.get(Character, id)
      :error -> nil
    end
  end

  @doc """
  Returns a changeset for tracking character changes.
  """
  def change_character(%Character{} = character, attrs \\ %{}) do
    character
    |> Map.put(:tag_list, character.tag_list || Tags.format(character.tags))
    |> Character.changeset(attrs)
  end

  @doc """
  Adds a character to the library, owned by the scope's user.
  """
  def create_character(%Scope{user: %User{} = user}, attrs) do
    %Character{owner_id: user.id}
    |> Character.changeset(attrs)
    |> Repo.insert()
  end

  def create_character(_scope, _attrs), do: {:error, :unauthorized}

  @doc """
  Returns true if the scope may change the character: its owner or a library
  editor (or admin).
  """
  def can_edit?(%Scope{user: %User{id: id}}, %Character{owner_id: id}), do: true
  def can_edit?(scope, %Character{}), do: Accounts.library_editor?(scope)

  @doc """
  Updates the character sheet.
  """
  def update_character(scope, %Character{} = character, attrs) do
    authorize(scope, character, fn ->
      character |> Character.changeset(attrs) |> Repo.update()
    end)
  end

  @doc """
  Replaces the character's avatar with an uploaded image.
  """
  def update_character_avatar(scope, %Character{} = character, image) when is_binary(image) do
    authorize(scope, character, fn -> replace_avatar(character, image) end)
  end

  defp replace_avatar(character, image) do
    Repo.transact(fn ->
      with {:ok, avatar} <- Avatars.create_avatar(image),
           {:ok, updated} <-
             character |> Ecto.Changeset.change(avatar_id: avatar.id) |> Repo.update() do
        :ok = Avatars.delete_avatar(character.avatar_id)
        {:ok, updated}
      end
    end)
  end

  @doc """
  Deletes the character, its avatar, and its place in every cast.
  """
  def delete_character(scope, %Character{} = character) do
    authorize(scope, character, fn -> delete_with_avatar(character) end)
  end

  defp delete_with_avatar(character) do
    Repo.transact(fn ->
      with {:ok, deleted} <- Repo.delete(character) do
        :ok = Avatars.delete_avatar(character.avatar_id)
        {:ok, deleted}
      end
    end)
  end

  defp authorize(scope, character, fun) do
    if can_edit?(scope, character), do: fun.(), else: {:error, :unauthorized}
  end
end
