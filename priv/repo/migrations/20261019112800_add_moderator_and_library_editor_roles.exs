defmodule HoloChat.Repo.Migrations.AddModeratorAndLibraryEditorRoles do
  use Ecto.Migration

  # Site-wide roles next to is_admin: moderators manage any room, library
  # editors edit any scenario and character.
  def change do
    alter table(:users) do
      add :is_moderator, :boolean, null: false, default: false
      add :is_library_editor, :boolean, null: false, default: false
    end
  end
end
