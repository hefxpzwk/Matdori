defmodule Matdori.RateLimiter do
  use GenServer

  @table __MODULE__

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def allow?(session_id, action, limit_per_minute) do
    allow?(session_id, action, limit_per_minute, :minute)
  end

  def allow?(session_id, action, limit, period) when period in [:second, :minute] do
    bucket =
      case period do
        :second -> System.system_time(:second)
        :minute -> System.system_time(:second) |> div(60)
      end

    key = {session_id, action, period, bucket}
    now = System.system_time(:second)

    count = :ets.update_counter(@table, key, {2, 1}, {key, 0, now})
    true = :ets.update_element(@table, key, {3, now})

    if count <= limit do
      :ok
    else
      {:error, :rate_limited}
    end
  end

  @impl true
  def init(_state) do
    :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
    Process.send_after(self(), :prune, :timer.minutes(2))
    {:ok, %{}}
  end

  @impl true
  def handle_info(:prune, state) do
    cutoff = System.system_time(:second) - 180

    :ets.select_delete(@table, [{{{:_, :_, :_}, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])

    Process.send_after(self(), :prune, :timer.minutes(2))
    {:noreply, state}
  end
end
