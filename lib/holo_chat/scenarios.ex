defmodule HoloChat.Scenarios do
  @moduledoc """
  The Scenarios context: a shared library of scenarios.

  A scenario describes where and when a story plays (title, topic line,
  description, card and background image) and suggests a cast. Role-play
  rooms play one scenario at a time (see `HoloChat.Rooms`). Any registered
  user can add scenarios; the owner and admins can change them.
  """

  use Boundary,
    deps: [HoloChat.Repo, HoloChat.Accounts, HoloChat.Avatars, HoloChat.Characters],
    exports: [Scenario]

  import Ecto.Query, warn: false

  alias HoloChat.{Accounts, Avatars, Characters}
  alias HoloChat.Accounts.{Scope, User}
  alias HoloChat.Characters.Tags
  alias HoloChat.Repo
  alias HoloChat.Scenarios.{CastMember, Scenario}

  @pubsub HoloChat.PubSub
  @topic "scenarios"
  @image_sizes %{card: {640, 360}, background: {1600, 900}}

  @doc """
  Subscribes to changes of any scenario: `{:scenario_updated, %Scenario{}}`.
  """
  def subscribe, do: Phoenix.PubSub.subscribe(@pubsub, @topic)

  @doc """
  Returns all scenarios, newest first.
  """
  def list_scenarios do
    Repo.all(from s in Scenario, order_by: [desc: s.inserted_at, desc: s.id])
  end

  @doc """
  Returns the scenarios with the given ids.
  """
  def list_scenarios_by_ids(ids), do: Repo.all(from s in Scenario, where: s.id in ^ids)

  @doc """
  Gets a scenario; nil if it doesn't exist or the id is malformed.
  """
  def get_scenario(id) do
    case Ecto.Type.cast(:id, id) do
      {:ok, id} -> Repo.get(Scenario, id)
      :error -> nil
    end
  end

  @doc """
  Returns a changeset for tracking scenario changes.
  """
  def change_scenario(%Scenario{} = scenario, attrs \\ %{}) do
    scenario
    |> Map.put(:tag_list, scenario.tag_list || Tags.format(scenario.tags))
    |> Scenario.changeset(attrs)
  end

  @doc """
  Adds a scenario to the library, owned by the scope's user.
  """
  def create_scenario(%Scope{user: %User{} = user}, attrs) do
    %Scenario{owner_id: user.id}
    |> Scenario.changeset(attrs)
    |> Repo.insert()
  end

  def create_scenario(_scope, _attrs), do: {:error, :unauthorized}

  @doc """
  Returns true if the scope may change the scenario: its owner or a library
  editor (or admin).
  """
  def can_edit?(%Scope{user: %User{id: id}}, %Scenario{owner_id: id}), do: true
  def can_edit?(scope, %Scenario{}), do: Accounts.library_editor?(scope)

  @doc """
  Updates the scenario's text and announces the change.
  """
  def update_scenario(scope, %Scenario{} = scenario, attrs) do
    authorize(scope, scenario, fn ->
      scenario |> Scenario.changeset(attrs) |> Repo.update() |> broadcast_update()
    end)
  end

  @doc """
  Replaces the scenario's `:card` (640x360) or `:background` (1600x900)
  image with an uploaded one, deleting the old image.
  """
  def update_scenario_image(scope, %Scenario{} = scenario, kind, image)
      when is_map_key(@image_sizes, kind) and is_binary(image) do
    authorize(scope, scenario, fn ->
      scenario
      |> replace_image(image_field(kind), @image_sizes[kind], image)
      |> broadcast_update()
    end)
  end

  defp replace_image(scenario, field, size, image) do
    Repo.transact(fn ->
      with {:ok, new_image} <- Avatars.create_avatar(image, size),
           {:ok, updated} <-
             scenario |> Ecto.Changeset.change([{field, new_image.id}]) |> Repo.update() do
        :ok = Avatars.delete_avatar(Map.fetch!(scenario, field))
        {:ok, updated}
      end
    end)
  end

  defp image_field(:card), do: :card_image_id
  defp image_field(:background), do: :background_image_id

  @doc """
  Returns the scenario's suggested cast, by name.
  """
  def list_cast(%Scenario{} = scenario), do: Characters.list_characters_by_ids(cast_ids(scenario))

  @doc """
  Suggests library characters for the scenario: those sharing its tags,
  most shared tags first, leaving out the ones already cast.
  """
  def suggest_cast(%Scenario{} = scenario, limit \\ 12) do
    Characters.suggest_characters(scenario.tags, cast_ids(scenario), limit)
  end

  @doc """
  Adds a library character to the suggested cast. Adding someone twice is
  harmless.
  """
  def cast_character(scope, %Scenario{} = scenario, character_id) do
    authorize(scope, scenario, fn ->
      case Characters.get_character(character_id) do
        nil ->
          {:error, :not_found}

        character ->
          Repo.insert!(%CastMember{scenario_id: scenario.id, character_id: character.id},
            on_conflict: :nothing
          )

          broadcast_update({:ok, scenario})
      end
    end)
  end

  @doc """
  Removes a character from the suggested cast.
  """
  def uncast_character(scope, %Scenario{} = scenario, character_id) do
    authorize(scope, scenario, fn ->
      Repo.delete_all(
        from cm in CastMember,
          where: cm.scenario_id == ^scenario.id and cm.character_id == ^character_id
      )

      broadcast_update({:ok, scenario})
    end)
  end

  defp cast_ids(%Scenario{id: scenario_id}) do
    Repo.all(
      from cm in CastMember, where: cm.scenario_id == ^scenario_id, select: cm.character_id
    )
  end

  defp authorize(scope, scenario, fun) do
    if can_edit?(scope, scenario), do: fun.(), else: {:error, :unauthorized}
  end

  defp broadcast_update({:ok, %Scenario{} = scenario} = result) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, {:scenario_updated, scenario})
    result
  end

  defp broadcast_update(error), do: error
end
