defmodule HoloChat.Repo.Migrations.CreatePromptTemplates do
  use Ecto.Migration

  def change do
    create table(:assistant_prompt_templates) do
      add :name, :string, null: false
      add :body, :text, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:assistant_prompt_templates, [:name])

    # Rooms without a template, or whose template was deleted, use the
    # built-in one.
    alter table(:rooms) do
      add :prompt_template_id,
          references(:assistant_prompt_templates, on_delete: :nilify_all)
    end
  end
end
