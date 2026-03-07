defmodule Matdori.XRoomSyncTest do
  use Matdori.DataCase, async: false

  alias Matdori.XRoomSync

  test "run_once/1 syncs provided source posts" do
    tweet_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, %{inserted_or_updated: 1, errors: []}} =
             XRoomSync.run_once(
               session_id: "x-room-sync-test",
               source_posts: [
                 %{
                   tweet_id: tweet_id,
                   tweet_url: "https://x.com/bbiribarabu/status/#{tweet_id}",
                   snapshot_text: "sync smoke text",
                   posted_at: ~U[2026-03-06 12:00:00Z]
                 }
               ]
             )
  end

  test "run_once/1 returns missing token when bearer token is unavailable" do
    previous_token = Application.get_env(:matdori, :x_bearer_token)
    Application.put_env(:matdori, :x_bearer_token, nil)
    on_exit(fn -> Application.put_env(:matdori, :x_bearer_token, previous_token) end)

    assert {:error, :missing_x_bearer_token} = XRoomSync.run_once(session_id: "missing-token")
  end
end
