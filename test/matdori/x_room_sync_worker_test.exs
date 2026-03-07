defmodule Matdori.XRoomSyncWorkerTest do
  use ExUnit.Case, async: false

  test "worker is disabled in test environment" do
    assert Application.get_env(:matdori, :x_periodic_sync_enabled) == false
    assert Process.whereis(Matdori.XRoomSyncWorker) == nil
  end
end
