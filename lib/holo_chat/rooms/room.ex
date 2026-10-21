defmodule HoloChat.Rooms.Room do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  schema "rooms" do
    field :name, :string
    field :kind, :string, default: "roleplay"
    field :reply_policy, :string, default: "natural"
    field :reply_delay, :integer, default: 4
    field :max_ai_turns, :integer, default: 2
    # When a player wears a character the AI plays here: "takeover" or "forbid".
    field :cloak_policy, :string, default: "takeover"
    # The assistant's prompt template for the cast; nil for the built-in one.
    # A plain id: Rooms doesn't depend on Assistant.
    field :prompt_template_id, :id
    belongs_to :scenario, HoloChat.Scenarios.Scenario

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for a new room: the name is chosen once and never changes, and
  the first scenario is picked. Later scenarios are switched to, see
  `HoloChat.Rooms.switch_scenario/3`.
  """
  def create_changeset(room, attrs) do
    room
    |> cast(attrs, [:name, :scenario_id])
    |> update_change(:name, &String.trim/1)
    |> validate_required([:name, :scenario_id])
    |> unique_constraint(:name, message: "is already taken")
    |> foreign_key_constraint(:scenario_id, message: "does not exist")
    |> changeset(attrs)
  end

  @doc """
  Changeset for the settings the game masters edit: how the cast takes turns,
  whether players may wear the cast's characters, and the cast's prompt
  template.
  """
  def changeset(room, attrs) do
    room
    |> cast(attrs, [
      :reply_policy,
      :reply_delay,
      :max_ai_turns,
      :cloak_policy,
      :prompt_template_id
    ])
    |> validate_inclusion(:reply_policy, ~w(natural mention))
    |> validate_inclusion(:cloak_policy, ~w(takeover forbid))
    |> validate_number(:reply_delay, greater_than_or_equal_to: 0, less_than_or_equal_to: 60)
    |> validate_number(:max_ai_turns, greater_than_or_equal_to: 1, less_than_or_equal_to: 5)
    |> foreign_key_constraint(:prompt_template_id, message: "does not exist")
  end
end
