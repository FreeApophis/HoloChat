defmodule HoloChatWeb.CharacterLive.Import do
  use HoloChatWeb, :live_view

  alias HoloChat.{Avatars, Cards, Characters, Scenarios}
  alias HoloChat.Characters.Character
  alias HoloChat.Scenarios.Scenario

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto w-full max-w-5xl py-8">
        <.header>
          Import a character card
          <:subtitle>
            SillyTavern cards mix a character with the scene it plays in. HoloChat keeps them
            apart: the card becomes a character for the library and a scenario that casts them.
            Check what goes where before importing.
          </:subtitle>
        </.header>

        <.form
          :if={!@character_form}
          for={%{}}
          id="card-upload-form"
          phx-change="select"
          phx-submit="read"
          class="flex flex-col items-center gap-4 rounded-2xl border border-dashed border-base-300 bg-base-100 px-6 py-12 text-center"
          phx-drop-target={@uploads.card.ref}
        >
          <.icon name="hero-arrow-up-tray" class="size-10 text-primary" />
          <div class="space-y-1">
            <p class="font-medium">Choose a card or drop it here</p>
            <p class="text-xs opacity-60">PNG card or JSON, V1 to V3, up to 10 MB.</p>
          </div>
          <.live_file_input upload={@uploads.card} class="file-input file-input-sm w-full max-w-sm" />
          <p :for={entry <- @uploads.card.entries} class="text-xs">
            {entry.client_name}
            <span :for={error <- upload_errors(@uploads.card, entry)} class="text-error">
              – {upload_error(error)}
            </span>
          </p>
          <p :if={@card_error} id="card-error" class="text-sm text-error">{@card_error}</p>
          <.button variant="primary" phx-disable-with="Reading…">Read card</.button>
        </.form>

        <.form
          :if={@character_form}
          for={@character_form}
          id="card-import-form"
          phx-change="validate"
          phx-submit="import"
        >
          <div class="grid gap-6 lg:grid-cols-2">
            <section
              id="card-character"
              class="rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm"
            >
              <h2 class="mb-1 flex items-center gap-2 text-lg font-semibold">
                <.icon name="hero-user" class="size-5 text-primary" /> Character
              </h2>
              <p class="mb-4 text-xs opacity-60">Who they are, wherever they are cast.</p>

              <div class="mb-4 flex items-center gap-4">
                <img
                  :if={@avatar}
                  id="card-avatar-preview"
                  src={"data:image/jpeg;base64," <> Base.encode64(@avatar)}
                  alt=""
                  class="size-20 rounded-full object-cover shadow-sm ring-2 ring-base-300"
                />
                <.avatar
                  :if={!@avatar}
                  name={@character_form[:name].value}
                  class="size-20 text-2xl"
                />
                <p class="text-xs opacity-60">
                  {if @avatar,
                    do: "The card's image becomes the avatar.",
                    else: "This card has no image. Add an avatar later."}
                </p>
              </div>

              <.input field={@character_form[:name]} type="text" label="Name" />
              <.input field={@character_form[:tag_list]} type="text" label="Tags" />
              <.input
                field={@character_form[:description]}
                type="textarea"
                label="Description"
                rows="8"
              />
              <.input
                field={@character_form[:personality]}
                type="textarea"
                label="Personality"
                rows="4"
              />
            </section>

            <section
              id="card-scenario"
              class={[
                "rounded-2xl border border-base-300 bg-base-100 p-5 shadow-sm transition",
                !@with_scenario && "opacity-70"
              ]}
            >
              <h2 class="mb-1 flex items-center gap-2 text-lg font-semibold">
                <.icon name="hero-map" class="size-5 text-primary" /> Scenario
              </h2>
              <p class="mb-4 text-xs opacity-60">
                Where and when the story plays, from the card's scenario and first message.
              </p>

              <.input
                type="checkbox"
                id="card-with-scenario"
                name="import[with_scenario]"
                value={@with_scenario}
                label="Also create this scenario, with the character in its cast"
              />

              <div :if={@with_scenario} class="mt-3">
                <.input field={@scenario_form[:title]} type="text" label="Title" />
                <.input
                  field={@scenario_form[:topic]}
                  type="text"
                  label="Topic"
                  placeholder="One line shown on the card and above the chat"
                />
                <.input field={@scenario_form[:tag_list]} type="text" label="Tags" />
                <.input
                  field={@scenario_form[:description]}
                  type="textarea"
                  label="Description"
                  rows="14"
                />
                <p class="-mt-1 text-xs opacity-60">
                  Add card and background images on the scenario's page after importing.
                </p>
              </div>
            </section>
          </div>

          <div class="mt-6 flex items-center gap-3">
            <.button variant="primary" phx-disable-with="Importing…">Import</.button>
            <button
              type="button"
              id="card-reset"
              phx-click="reset"
              class="rounded-lg px-3 py-2 text-sm opacity-70 transition hover:bg-base-200 hover:opacity-100"
            >
              Choose another card
            </button>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Import a card")
     |> allow_upload(:card, accept: ~w(.png .json), max_entries: 1, max_file_size: 10_000_000)
     |> reset()}
  end

  defp reset(socket) do
    socket
    |> assign(:card_error, nil)
    |> assign(:avatar, nil)
    |> assign(:with_scenario, false)
    |> assign(:character_form, nil)
    |> assign(:scenario_form, nil)
  end

  @impl true
  def handle_event("select", _params, socket), do: {:noreply, assign(socket, :card_error, nil)}

  def handle_event("read", _params, socket) do
    files =
      consume_uploaded_entries(socket, :card, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    case files do
      [file] -> {:noreply, read_card(socket, file)}
      [] -> {:noreply, assign(socket, :card_error, "Choose a card first.")}
    end
  end

  def handle_event("validate", params, socket) do
    {:noreply, assign_forms(socket, params, :validate)}
  end

  def handle_event("import", %{"character" => character_params} = params, socket) do
    scenario_params = if with_scenario?(params), do: Map.get(params, "scenario", %{})
    scope = socket.assigns.current_scope

    case Cards.import_card(scope, character_params, scenario_params, socket.assigns.avatar) do
      {:ok, %{character: character, scenario: scenario}} ->
        {:noreply,
         socket
         |> put_flash(:info, imported(character, scenario))
         |> push_navigate(to: ~p"/characters/#{character.id}")}

      {:error, %Ecto.Changeset{}} ->
        {:noreply, assign_forms(socket, params, :insert)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "The card could not be imported.")}
    end
  end

  def handle_event("reset", _params, socket), do: {:noreply, reset(socket)}

  defp read_card(socket, file) do
    case Cards.read(file) do
      {:ok, draft} ->
        socket
        |> assign(:avatar, preview(draft.image))
        |> assign(:with_scenario, draft.scenario != nil)
        # Validated right away, so fields the card overfills show at once.
        |> assign(
          :character_form,
          to_form(Characters.change_character(%Character{}, draft.character), action: :validate)
        )
        |> assign(
          :scenario_form,
          to_form(Scenarios.change_scenario(%Scenario{}, draft.scenario || %{}),
            action: :validate
          )
        )

      {:error, :invalid_card} ->
        assign(socket, :card_error, "This file is not a character card.")
    end
  end

  # The avatar as it will be stored; a card whose image can't be decoded is
  # imported without one.
  defp preview(nil), do: nil

  defp preview(image) do
    case Avatars.process(image) do
      {:ok, jpeg} -> jpeg
      {:error, :invalid_image} -> nil
    end
  end

  defp assign_forms(socket, params, action) do
    character =
      %Character{}
      |> Characters.change_character(Map.get(params, "character", %{}))
      |> Map.put(:action, action)

    scenario =
      %Scenario{}
      |> Scenarios.change_scenario(
        Map.get(params, "scenario", socket.assigns.scenario_form.params)
      )
      |> Map.put(:action, action)

    socket
    |> assign(:with_scenario, with_scenario?(params))
    |> assign(:character_form, to_form(character))
    |> assign(:scenario_form, to_form(scenario))
  end

  defp with_scenario?(params), do: get_in(params, ["import", "with_scenario"]) == "true"

  defp imported(character, nil), do: "Imported #{character.name}."

  defp imported(character, scenario),
    do: "Imported #{character.name} and the scenario “#{scenario.title}”."

  defp upload_error(:too_large), do: "larger than 10 MB"
  defp upload_error(:not_accepted), do: "not a PNG or JSON file"
  defp upload_error(:too_many_files), do: "only one card at a time"
  defp upload_error(error), do: inspect(error)
end
