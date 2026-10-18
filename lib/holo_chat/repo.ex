defmodule HoloChat.Repo do
  use Boundary

  use Ecto.Repo,
    otp_app: :holo_chat,
    adapter: Ecto.Adapters.Postgres
end
