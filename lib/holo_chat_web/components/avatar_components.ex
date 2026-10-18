defmodule HoloChatWeb.AvatarComponents do
  @moduledoc """
  Avatars for people and assistant personas.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: HoloChatWeb.Endpoint,
    router: HoloChatWeb.Router,
    statics: HoloChatWeb.static_paths()

  import HoloChatWeb.CoreComponents, only: [icon: 1]

  # Literal class strings so Tailwind picks them up.
  @colors ~w(
    bg-rose-500 bg-orange-500 bg-amber-500 bg-lime-600 bg-emerald-600
    bg-teal-600 bg-sky-600 bg-indigo-500 bg-violet-500 bg-fuchsia-600
  )

  @doc """
  Renders an avatar: the uploaded image if there is one, otherwise the
  name's initial on a color derived from the name (or a sparkle for
  assistants).
  """
  attr :name, :string, required: true
  attr :avatar_id, :string, default: nil
  attr :assistant, :boolean, default: false
  attr :class, :any, default: "size-9 text-sm", doc: "size and text size"
  attr :rest, :global

  def avatar(%{avatar_id: avatar_id} = assigns) when is_binary(avatar_id) do
    ~H"""
    <img
      src={~p"/avatars/#{@avatar_id}"}
      alt={@name}
      class={["shrink-0 rounded-full bg-base-200 object-cover", @class]}
      {@rest}
    />
    """
  end

  def avatar(assigns) do
    ~H"""
    <div
      class={[
        "grid shrink-0 place-items-center rounded-full font-semibold text-white",
        if(@assistant, do: "bg-gradient-to-br from-violet-500 to-fuchsia-500", else: color(@name)),
        @class
      ]}
      aria-label={@name}
      {@rest}
    >
      <%= if @assistant do %>
        <.icon name="hero-sparkles" class="size-1/2" />
      <% else %>
        {initial(@name)}
      <% end %>
    </div>
    """
  end

  defp initial(name), do: name |> String.first() |> String.upcase()

  defp color(name), do: Enum.at(@colors, :erlang.phash2(name, length(@colors)))
end
