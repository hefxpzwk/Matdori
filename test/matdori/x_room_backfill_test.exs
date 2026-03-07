defmodule Matdori.XRoomBackfillTest do
  use Matdori.DataCase, async: false

  alias Matdori.XRoomBackfill
  alias Matdori.XSyncState

  test "run/1 dry-run reports planned upserts from source pages" do
    first_id = Integer.to_string(System.unique_integer([:positive]))
    second_id = Integer.to_string(System.unique_integer([:positive]))

    pages = [
      %{
        posts: [
          %{
            tweet_id: first_id,
            tweet_url: "https://x.com/bbiribarabu/status/#{first_id}",
            snapshot_text: "first",
            posted_at: ~U[2026-03-06 10:00:00Z]
          },
          %{
            tweet_id: second_id,
            tweet_url: "https://x.com/bbiribarabu/status/#{second_id}",
            snapshot_text: "second",
            posted_at: ~U[2026-03-06 11:00:00Z]
          }
        ],
        next_token: nil
      }
    ]

    assert {:ok, summary} =
             XRoomBackfill.run(
               dry_run: true,
               resume: false,
               username: "bbiribarabu",
               source_pages: pages,
               max_posts: 50,
               batch_size: 50
             )

    assert summary.dry_run
    assert summary.planned_upserts == 2
    assert summary.inserted_or_updated == 0
    assert summary.completed
  end

  test "run/1 resume returns no-op when backfill already completed" do
    tweet_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, first_summary} =
             XRoomBackfill.run(
               dry_run: false,
               resume: true,
               username: "bbiribarabu",
               source_pages: [
                 %{
                   posts: [
                     %{
                       tweet_id: tweet_id,
                       tweet_url: "https://x.com/bbiribarabu/status/#{tweet_id}",
                       snapshot_text: "backfill text",
                       posted_at: ~U[2026-03-06 12:00:00Z]
                     }
                   ],
                   next_token: nil
                 }
               ],
               max_posts: 50,
               batch_size: 50,
               session_id: "backfill-resume"
             )

    assert first_summary.completed

    assert {:ok, second_summary} =
             XRoomBackfill.run(
               dry_run: false,
               resume: true,
               username: "bbiribarabu",
               max_posts: 50,
               batch_size: 50
             )

    assert second_summary.pages == 0
    assert second_summary.planned_upserts == 0
    assert second_summary.inserted_or_updated == 0
    assert second_summary.completed
  end

  test "run/1 with dry-run and resume does not mutate sync state" do
    tweet_id = Integer.to_string(System.unique_integer([:positive]))

    assert {:ok, summary} =
             XRoomBackfill.run(
               dry_run: true,
               resume: true,
               username: "bbiribarabu",
               source_pages: [
                 %{
                   posts: [
                     %{
                       tweet_id: tweet_id,
                       tweet_url: "https://x.com/bbiribarabu/status/#{tweet_id}",
                       snapshot_text: "dry run",
                       posted_at: ~U[2026-03-06 12:00:00Z]
                     }
                   ],
                   next_token: nil
                 }
               ],
               max_posts: 10,
               batch_size: 10,
               session_id: "backfill-dry-run"
             )

    assert summary.dry_run
    assert Repo.get_by(XSyncState, source_username: "bbiribarabu") == nil
  end
end
