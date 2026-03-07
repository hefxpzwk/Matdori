defmodule Mix.Tasks.Matdori.SyncRoomsOnce do
  use Mix.Task

  alias Matdori.XRoomSync

  @shortdoc "Runs one X room sync cycle"

  @impl true
  def run(args) do
    {opts, _rest, invalid} = OptionParser.parse(args, switches: [session_id: :string])

    if invalid != [] do
      Mix.raise("invalid options: #{inspect(invalid)}")
    end

    Mix.Task.run("app.start")

    session_id = Keyword.get(opts, :session_id, "mix:sync-once")

    case XRoomSync.run_once(session_id: session_id) do
      {:ok, summary} ->
        errors = Map.get(summary, :errors, [])

        Mix.shell().info(
          "sync_rooms_once inserted_or_updated=#{summary.inserted_or_updated} errors_count=#{length(errors)} session_id=#{session_id}"
        )

      {:error, reason} ->
        Mix.raise("sync_rooms_once failed: #{inspect(reason)}")
    end
  end
end
