defmodule Matdori.XRoomSyncWorker do
  @moduledoc false

  use GenServer

  require Logger

  alias Matdori.Repo
  alias Matdori.XRoomSync

  @advisory_lock_key 4_900_001
  @default_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_sync(0)
    {:ok, %{interval_ms: sync_interval_ms(), missing_config_logged?: false}}
  end

  @impl true
  def handle_info(:sync, state) do
    state =
      if missing_x_config?() do
        if !state.missing_config_logged? do
          Logger.warning(
            "[x_room_sync_worker] skipped periodic sync because X_BEARER_TOKEN or X_SOURCE_USERNAME is missing"
          )
        end

        %{state | missing_config_logged?: true}
      else
        run_periodic_sync()
        %{state | missing_config_logged?: false}
      end

    schedule_sync(state.interval_ms)
    {:noreply, state}
  end

  defp run_periodic_sync do
    Repo.transaction(fn ->
      case Repo.query("SELECT pg_try_advisory_xact_lock($1)", [@advisory_lock_key]) do
        {:ok, %Postgrex.Result{rows: [[true]]}} ->
          _ = XRoomSync.run_once(session_id: "system:periodic")

        {:ok, %Postgrex.Result{rows: [[false]]}} ->
          Logger.debug("[x_room_sync_worker] skipped periodic sync because lock is held")

        {:error, reason} ->
          Logger.warning(
            "[x_room_sync_worker] failed to acquire advisory lock: #{inspect(reason)}"
          )
      end
    end)
  end

  defp schedule_sync(delay_ms) do
    Process.send_after(self(), :sync, delay_ms)
  end

  defp sync_interval_ms do
    case Application.get_env(:matdori, :x_periodic_sync_interval_ms, @default_interval_ms) do
      value when is_integer(value) and value > 0 -> value
      _ -> @default_interval_ms
    end
  end

  defp missing_x_config? do
    missing?(Application.get_env(:matdori, :x_bearer_token)) or
      missing?(Application.get_env(:matdori, :x_source_username))
  end

  defp missing?(value) when is_binary(value), do: String.trim(value) == ""
  defp missing?(_value), do: true
end
