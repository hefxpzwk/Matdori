defmodule MatdoriWeb.Presence do
  use Phoenix.Presence,
    otp_app: :matdori,
    pubsub_server: Matdori.PubSub
end
