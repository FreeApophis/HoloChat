defmodule HoloChat.Repo.Migrations.AddLanguageToPromptTemplates do
  use Ecto.Migration

  def change do
    # Templates are offered in rooms that speak their language.
    alter table(:assistant_prompt_templates) do
      add :language, :string, null: false, default: "en"
    end
  end
end
