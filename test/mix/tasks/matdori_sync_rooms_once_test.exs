defmodule Mix.Tasks.Matdori.SyncRoomsOnceTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  test "run/1 raises when X_BEARER_TOKEN is missing" do
    previous_token = Application.get_env(:matdori, :x_bearer_token)
    Application.put_env(:matdori, :x_bearer_token, nil)
    on_exit(fn -> Application.put_env(:matdori, :x_bearer_token, previous_token) end)

    Mix.Task.reenable("matdori.sync_rooms_once")

    assert_raise Mix.Error, fn ->
      capture_io(fn -> Mix.Tasks.Matdori.SyncRoomsOnce.run([]) end)
    end
  end
end
