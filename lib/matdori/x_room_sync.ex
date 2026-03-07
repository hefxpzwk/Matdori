defmodule Matdori.XRoomSync do
  @moduledoc false

  require Logger

  alias Matdori.Collab

  @telemetry_prefix [:matdori, :x_room_sync]

  def run_once(opts \\ []) do
    started_at = System.monotonic_time()
    session_id = Keyword.get(opts, :session_id, "x-sync")

    sync_opts =
      opts
      |> Keyword.drop([:session_id])
      |> Keyword.put(:session_id, session_id)

    result = Collab.sync_configured_account_posts(sync_opts)
    duration = System.monotonic_time() - started_at

    case result do
      {:ok, summary} ->
        errors = Map.get(summary, :errors, [])

        :telemetry.execute(
          @telemetry_prefix ++ [:success],
          %{
            duration: duration,
            inserted_or_updated: summary.inserted_or_updated,
            errors_count: length(errors)
          },
          %{session_id: session_id}
        )

        Logger.info(
          "[x_room_sync] success inserted_or_updated=#{summary.inserted_or_updated} errors_count=#{length(errors)} session_id=#{session_id}"
        )

        {:ok, summary}

      {:error, reason} = error ->
        :telemetry.execute(
          @telemetry_prefix ++ [:error],
          %{duration: duration},
          %{session_id: session_id, reason: inspect(reason)}
        )

        Logger.warning("[x_room_sync] failed reason=#{inspect(reason)} session_id=#{session_id}")
        error
    end
  end
end
