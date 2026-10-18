defmodule HoloChatWeb.UserLive.AccountComponents do
  @moduledoc """
  Pieces shared by the account LiveViews.
  """
  use Phoenix.Component

  @doc """
  Renders recovery codes for the user to copy, one per list item.
  """
  attr :id, :string, required: true
  attr :codes, :list, required: true

  def recovery_code_list(assigns) do
    ~H"""
    <ol
      id={@id}
      class="mt-6 grid grid-cols-2 gap-2 rounded-xl border border-base-300 bg-base-200 p-4 font-mono text-sm"
    >
      <li :for={code <- @codes} class="select-all rounded-md bg-base-100 px-2 py-1.5 text-center">
        {code}
      </li>
    </ol>
    """
  end

  @doc """
  The client IP of a LiveView connection, for rate limiting.

  Only available during mount. Returns `nil` when unknown.
  """
  def client_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> address
      _ -> nil
    end
  end
end
