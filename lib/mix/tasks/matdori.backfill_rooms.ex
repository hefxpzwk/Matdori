defmodule Mix.Tasks.Matdori.BackfillRooms do
  use Mix.Task

  alias Matdori.XRoomBackfill

  @shortdoc "Backfills room posts from X timeline with resume/dry-run options"

  @switches [
    dry_run: :boolean,
    resume: :boolean,
    max_posts: :integer,
    batch_size: :integer,
    sleep_ms: :integer,
    session_id: :string,
    username: :string
  ]

  @impl true
  def run(args) do
    {opts, _rest, invalid} = OptionParser.parse(args, switches: @switches)

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    Mix.Task.run("app.start")

    case XRoomBackfill.run(opts) do
      {:ok, summary} ->
        Mix.shell().info(summary_line(summary))

      {:error, reason} ->
        Mix.raise("backfill_rooms failed: #{inspect(reason)}")
    end
  end

  defp summary_line(summary) do
    [
      "backfill_rooms",
      "dry_run=#{summary.dry_run}",
      "resume=#{summary.resume}",
      "source_username=#{summary.source_username}",
      "pages=#{summary.pages}",
      "scanned_posts=#{summary.scanned_posts}",
      "processed_posts=#{summary.processed_posts}",
      "planned_upserts=#{summary.planned_upserts}",
      "inserted_or_updated=#{summary.inserted_or_updated}",
      "completed=#{summary.completed}",
      "next_token=#{summary.next_token || "nil"}"
    ]
    |> Enum.join(" ")
  end
end
