defmodule HoloChat do
  @moduledoc """
  HoloChat keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  use Boundary,
    deps: [],
    exports: [
      Accounts,
      Accounts.User,
      Accounts.Scope,
      Assistant,
      Assistant.Settings,
      Avatars,
      Avatars.Avatar,
      Assistant.Persona,
      Assistant.Server,
      Chat,
      Chat.Message,
      Characters,
      Characters.Character,
      Characters.Tags,
      Rooms,
      Rooms.Room,
      Scenarios,
      Scenarios.Scenario
    ]
end
