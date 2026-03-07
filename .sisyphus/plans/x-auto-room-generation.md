# Auto Room Generation From X Posts

## TL;DR
> **Summary**: Convert X ingestion from request-coupled sync to production-safe periodic sync so each X post reliably maps to its own room, with resumable full backfill for historical posts.
> **Deliverables**:
> - Periodic sync worker and one-shot sync entrypoint
> - DB-level idempotency guard (`tweet_id` uniqueness)
> - Resumable full backfill Mix task with dry-run/throttling
> - Updated RoomLive fallback behavior and operational observability
> **Effort**: Medium
> **Parallel**: YES - 3 waves
> **Critical Path**: T1 DB invariants -> T3 sync orchestration -> T5 periodic worker -> T7 verification

## Context
### Original Request
- New X posts should automatically create new rooms.
- Existing X posts should each have their own room.

### Interview Summary
- Sync model: periodic server-side sync as primary + on-visit fallback.
- Room policy: historical rooms remain interactive.
- Backfill scope: full backfill.
- Test strategy: tests-after.
- Backfill run mode: resumable Mix task.

### Metis Review (gaps addressed)
- Add DB-enforced idempotency for `tweet_id` (not app-level only).
- Prevent multi-node duplicate periodic sync execution (DB advisory lock or single-node scheduler contract).
- Replace silent sync failure with structured logs/telemetry.
- Backfill must support dry-run, throttle, max bounds, resumability.

## Work Objectives
### Core Objective
Ensure room creation is deterministic and automatic: one X post (`tweet_id`) produces one persistent room (`posts` row), independent of user visits.

### Deliverables
- Migration(s) and data cleanup path for robust `tweet_id` uniqueness.
- Shared sync service API used by periodic worker, fallback trigger, and Mix tasks.
- Periodic worker supervised in application tree with safe lock strategy.
- Mix tasks for one-shot sync and resumable full backfill.
- Tests covering idempotency, concurrency guardrails, and fallback semantics.

### Definition of Done (verifiable conditions with commands)
- `mix test`
- `mix precommit`
- `mix matdori.sync_rooms_once`
- `mix matdori.backfill_rooms --dry-run --max-posts 50`
- `mix matdori.backfill_rooms --resume --max-posts 50`

### Must Have
- No new Room schema; keep `Post` as room identity and `/rooms/:post_id` semantics.
- DB-level uniqueness for room identity (`tweet_id`) with safe migration behavior.
- Periodic sync not tied to HTTP request path.
- Backfill resumable and idempotent with explicit summary output.
- Single configured source account scope (`x_source_username`) for this plan version.

### Must NOT Have (guardrails, AI slop patterns, scope boundaries)
- No UI redesign or non-X ingestion scope.
- No irreversible destructive data rewrite without guarded migration path.
- No silent failure paths for periodic sync/backfill.
- No dependency sprawl unless justified (prefer existing OTP + current stack first).

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.
- Test decision: tests-after with ExUnit + Mix task assertions.
- QA policy: Every task includes happy and failure scenarios.
- Evidence: `.sisyphus/evidence/task-{N}-{slug}.{ext}`

## Execution Strategy
### Parallel Execution Waves
> Target: 5-8 tasks per wave. <3 per wave (except final) = under-splitting.
> Extract shared dependencies as Wave-1 tasks for max parallelism.

Wave 1: Data integrity + sync surface refactor foundations
Wave 2: Scheduler, fallback behavior, and backfill interface
Wave 3: End-to-end verification and docs/hardening

### Dependency Matrix (full, all tasks)
- T1 -> blocks T3, T4, T5, T6
- T2 -> blocks T3, T5, T6
- T3 -> blocks T4, T5, T6, T7
- T4 -> blocks T7
- T5 -> blocks T7
- T6 -> blocks T7
- T7 -> blocks T8
- T8 -> terminal

### Agent Dispatch Summary (wave -> task count -> categories)
- Wave 1 -> 3 tasks -> deep, unspecified-high
- Wave 2 -> 3 tasks -> deep, unspecified-high, quick
- Wave 3 -> 2 tasks -> unspecified-high, writing

## TODOs

- [ ] 1. Enforce DB idempotency for room identity (`tweet_id`)

  **What to do**: Add migration to (a) detect and resolve duplicate/null `tweet_id` rows safely, then (b) add `NOT NULL` + unique index/constraint on `posts.tweet_id`. Keep existing `tweet_url` uniqueness.
  **Must NOT do**: Do not drop historical rows blindly; do not break rollback path.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: schema/data integrity with migration safety.
  - Skills: `[]` — existing Ecto migration patterns are sufficient.
  - Omitted: `playwright` — no browser work.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [3,4,5,6] | Blocked By: []

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `priv/repo/migrations/20260306013000_allow_multiple_posts_per_day.exs` — migration style and `up/down` structure.
  - API/Type: `lib/matdori/collab/post.ex:8` — `tweet_id` field definition.
  - API/Type: `lib/matdori/collab.ex:310` — current `tweet_id`-first upsert lookup flow.
  - Test: `test/matdori/collab_test.exs:38` — sync/idempotency behavioral baseline.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `mix ecto.migrate` succeeds with new migration.
  - [ ] `mix run -e "import Ecto.Query; alias Matdori.{Repo, Collab.Post}; IO.puts(Repo.aggregate(from(p in Post, where: is_nil(p.tweet_id)), :count, :id))"` prints `0`.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Happy path - uniqueness enforced
    Tool: Bash
    Steps: Run migration; attempt two inserts with same tweet_id via mix run helper.
    Expected: Second insert fails with unique constraint violation.
    Evidence: .sisyphus/evidence/task-1-tweet-id-unique.txt

  Scenario: Failure/edge case - rollback safety
    Tool: Bash
    Steps: Run migration down/up cycle on local DB.
    Expected: Commands succeed without schema corruption.
    Evidence: .sisyphus/evidence/task-1-tweet-id-unique-error.txt
  ```

  **Commit**: YES | Message: `feat(db): enforce unique tweet_id for room identity` | Files: `priv/repo/migrations/*`, `lib/matdori/collab/post.ex`

- [ ] 2. Introduce shared sync service boundary for one-shot + periodic ingestion

  **What to do**: Extract/introduce a sync orchestration function/module (service layer) that runs one ingestion cycle, returns structured summary, and emits success/failure logs/telemetry.
  **Must NOT do**: Do not keep silent error swallowing as final behavior.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: refactor + reliability instrumentation.
  - Skills: `[]` — repo-specific patterns are enough.
  - Omitted: `playwright` — non-UI.

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: [3,5,6] | Blocked By: [1]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `lib/matdori/collab.ex:69` — `sync_configured_account_posts/1` contract.
  - Pattern: `lib/matdori/x_timeline.ex:8` — source fetch behavior and errors.
  - Pattern: `lib/matdori_web/live/room_live.ex:350` — current fallback caller behavior.
  - Test: `test/matdori/collab_test.exs:68` — re-sync snapshot version expectations.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `mix test test/matdori/collab_test.exs` passes.
  - [ ] `mix run -e "IO.inspect(Matdori.Collab.sync_configured_account_posts(session_id: \"smoke\"))"` returns structured tuple and no crash.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Happy path - one cycle sync summary
    Tool: Bash
    Steps: Execute one-shot sync with valid source_posts override.
    Expected: Summary includes inserted_or_updated count and empty errors.
    Evidence: .sisyphus/evidence/task-2-sync-service.txt

  Scenario: Failure/edge case - missing bearer token
    Tool: Bash
    Steps: Unset X_BEARER_TOKEN and run one-shot sync.
    Expected: Deterministic error signaling (logged + returned), not silent success.
    Evidence: .sisyphus/evidence/task-2-sync-service-error.txt
  ```

  **Commit**: YES | Message: `refactor(sync): centralize room ingestion cycle` | Files: `lib/matdori/collab.ex`, `lib/matdori/x_timeline.ex`, new sync module if added

- [ ] 3. Add periodic sync worker with single-run guard in supervision tree

  **What to do**: Add OTP worker supervised in `Matdori.Application` that runs periodic sync interval, with DB advisory lock (or equivalent) to avoid duplicate runs in multi-node deployments.
  **Must NOT do**: Do not rely on ETS-only lock semantics for cluster-wide single-run guarantees.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: scheduler + distributed safety concerns.
  - Skills: `[]` — OTP primitives and DB lock usage.
  - Omitted: `playwright` — non-UI.

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: [4,5,6,7] | Blocked By: [1,2]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `lib/matdori/application.ex:10` — supervised children registration.
  - Pattern: `lib/matdori/rate_limiter.ex:1` — existing GenServer style and timer pattern.
  - API/Type: `config/runtime.exs:26` — runtime env dependency pattern.
  - External: `https://hexdocs.pm/elixir/GenServer.html` — timer loop pattern.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `mix test` passes including new worker tests.
  - [ ] `mix run -e "IO.puts(Process.whereis(Matdori.XRoomSyncWorker) != nil)"` prints `true` (or chosen module name).

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Happy path - worker runs periodic cycle
    Tool: Bash
    Steps: Start app and observe at least one scheduled sync execution log.
    Expected: One cycle runs and emits summary telemetry/log.
    Evidence: .sisyphus/evidence/task-3-periodic-worker.txt

  Scenario: Failure/edge case - concurrent run protection
    Tool: Bash
    Steps: Force two immediate sync triggers.
    Expected: Second run skips/defers due to lock; no duplicate upsert side effects.
    Evidence: .sisyphus/evidence/task-3-periodic-worker-error.txt
  ```

  **Commit**: YES | Message: `feat(sync): add periodic room sync worker with lock` | Files: `lib/matdori/application.ex`, new worker module, config files

- [ ] 4. Keep `/rooms/latest` fallback lightweight and non-blocking

  **What to do**: Update `RoomLive` fallback behavior so page render does not perform heavy sync inline; instead trigger lightweight enqueue/request or stale-check pathway against new sync service.
  **Must NOT do**: Do not regress current route behavior (`/rooms/latest`, `/rooms/:post_id`).

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: LiveView flow changes + behavior preservation.
  - Skills: `[]` — existing LiveView patterns apply.
  - Omitted: `playwright` — not required for initial implementation.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [7] | Blocked By: [1,3]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `lib/matdori_web/live/room_live.ex:38` — `handle_params` entry.
  - Pattern: `lib/matdori_web/live/room_live.ex:350` — current sync fallback path.
  - API/Type: `lib/matdori/collab.ex:39` — latest post query contract.
  - Test: `assets/tests/e2e/realtime.spec.ts:9` — existing room navigation behavior.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `mix test` passes including RoomLive behavior tests.
  - [ ] `mix run -e "IO.puts(Matdori.Collab.get_latest_post_with_versions() != nil)"` still works with unchanged route semantics.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Happy path - latest room remains responsive
    Tool: Bash
    Steps: Hit /rooms/latest while sync service active.
    Expected: Room renders immediately with current latest post.
    Evidence: .sisyphus/evidence/task-4-latest-fallback.txt

  Scenario: Failure/edge case - sync error path
    Tool: Bash
    Steps: Simulate missing token and load /rooms/latest.
    Expected: Page still renders with deterministic degraded state; error logged.
    Evidence: .sisyphus/evidence/task-4-latest-fallback-error.txt
  ```

  **Commit**: YES | Message: `refactor(room-live): make latest sync fallback non-blocking` | Files: `lib/matdori_web/live/room_live.ex`

- [ ] 5. Implement resumable full backfill Mix task (`matdori.backfill_rooms`)

  **What to do**: Add Mix task supporting `--dry-run`, `--resume`, `--max-posts`, `--batch-size`, `--sleep-ms`, and deterministic summary output; use shared sync service/upsert path to avoid divergent logic.
  **Must NOT do**: Do not create one-shot irreversible script without resumability.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: operational safety and resumable workflow design.
  - Skills: `[]` — Mix + repo query patterns in-project.
  - Omitted: `playwright` — non-UI.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [7] | Blocked By: [1,2,3]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `priv/repo/e2e_seed.exs:11` — existing sync invocation style.
  - Pattern: `lib/matdori/collab.ex:302` — source_posts override path.
  - API/Type: `lib/matdori/x_timeline.ex:9` — max_results constraints.
  - Test: `test/matdori/collab_test.exs:113` — source username filter expectations.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `mix matdori.backfill_rooms --dry-run --max-posts 50` exits 0 and prints summary with `dry_run=true`.
  - [ ] Two consecutive runs `mix matdori.backfill_rooms --resume --max-posts 50` show second run with `planned_upserts=0` (or equivalent idempotent result).

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Happy path - resumable backfill
    Tool: Bash
    Steps: Run resume mode twice with same bounds.
    Expected: First run applies work, second run is no-op summary.
    Evidence: .sisyphus/evidence/task-5-backfill.txt

  Scenario: Failure/edge case - throttling and bounds
    Tool: Bash
    Steps: Run with invalid/zero batch size and with strict max-posts.
    Expected: Invalid args fail clearly; bounded run respects max-posts.
    Evidence: .sisyphus/evidence/task-5-backfill-error.txt
  ```

  **Commit**: YES | Message: `feat(tasks): add resumable full room backfill task` | Files: `lib/mix/tasks/*`, related service modules

- [ ] 6. Add one-shot operational sync task (`matdori.sync_rooms_once`) and runtime guards

  **What to do**: Add explicit one-shot command for ops/recovery paths; ensure missing config behavior is explicit and testable (not silent).
  **Must NOT do**: Do not return success with no signal when critical config is missing.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: focused operational CLI wrapper.
  - Skills: `[]` — straightforward Mix task pattern.
  - Omitted: `playwright` — non-UI.

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: [7] | Blocked By: [1,2,3]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `docs/deployment.md:9` — env dependencies to validate.
  - API/Type: `config/runtime.exs:27` — token/username runtime sources.
  - Pattern: `lib/matdori/collab.ex:69` — underlying sync API.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `mix matdori.sync_rooms_once` returns clear success summary when configured.
  - [ ] With missing token, command exits non-zero (or explicit deterministic disabled outcome, chosen and tested).

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Happy path - one-shot sync
    Tool: Bash
    Steps: Execute mix matdori.sync_rooms_once in configured env.
    Expected: Summary output with inserted_or_updated and errors fields.
    Evidence: .sisyphus/evidence/task-6-sync-once.txt

  Scenario: Failure/edge case - missing config
    Tool: Bash
    Steps: Unset X_BEARER_TOKEN and execute command.
    Expected: Explicit failure signal + actionable message.
    Evidence: .sisyphus/evidence/task-6-sync-once-error.txt
  ```

  **Commit**: YES | Message: `feat(tasks): add one-shot room sync command` | Files: `lib/mix/tasks/*`, `docs/deployment.md`

- [ ] 7. Add tests for ingestion idempotency, scheduler behavior, and task contracts

  **What to do**: Add/extend ExUnit coverage for periodic worker guard behavior, fallback semantics, unique tweet identity assumptions, and Mix task output contracts.
  **Must NOT do**: Do not rely on manual browser-only validation.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: multi-surface automated verification.
  - Skills: `[]` — existing test infrastructure is enough.
  - Omitted: `playwright` — optional only if UI behavior regresses.

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [8] | Blocked By: [3,4,5,6]

  **References** (executor has NO interview context — be exhaustive):
  - Test: `test/matdori/collab_test.exs` — sync/version/filter patterns.
  - Test: `test/matdori/rate_limiter_test.exs` — rate-limiter assertion style.
  - Pattern: `assets/tests/e2e/realtime.spec.ts` — existing room route smoke pattern.
  - API/Type: `lib/matdori_web/live/room_live.ex` — latest/show route behavior.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `mix test` passes with new assertions.
  - [ ] Tests include one deterministic missing-token failure path for sync task.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Happy path - periodic + backfill contract tests
    Tool: Bash
    Steps: Run full test suite after implementing tasks and worker.
    Expected: 0 failures and coverage of new sync pathways.
    Evidence: .sisyphus/evidence/task-7-tests.txt

  Scenario: Failure/edge case - duplicate tweet_id protection
    Tool: Bash
    Steps: Execute test that attempts duplicate tweet_id ingestion.
    Expected: Constraint violation handled gracefully; no duplicate room rows.
    Evidence: .sisyphus/evidence/task-7-tests-error.txt
  ```

  **Commit**: YES | Message: `test(sync): cover worker backfill and idempotency contracts` | Files: `test/**/*`, optional support fixtures

- [ ] 8. Update operational docs and run final precommit verification

  **What to do**: Document periodic sync behavior, fallback semantics, new Mix commands, and backfill runbook; execute precommit checks and capture evidence.
  **Must NOT do**: Do not leave runbook ambiguity around resume/dry-run usage.

  **Recommended Agent Profile**:
  - Category: `writing` — Reason: concise operational documentation and checklists.
  - Skills: `[]` — project docs style is simple markdown.
  - Omitted: `playwright` — no UI scope.

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: [] | Blocked By: [7]

  **References** (executor has NO interview context — be exhaustive):
  - Pattern: `docs/deployment.md` — env/runtime deployment style.
  - Pattern: `README.md` — local run command style.
  - API/Type: new Mix task names from T5/T6.

  **Acceptance Criteria** (agent-executable only):
  - [ ] `mix precommit` exits 0.
  - [ ] `docs/deployment.md` includes commands for `matdori.sync_rooms_once` and `matdori.backfill_rooms` with `--dry-run`/`--resume` examples.

  **QA Scenarios** (MANDATORY — task incomplete without these):
  ```
  Scenario: Happy path - runbook completeness
    Tool: Bash
    Steps: Execute documented commands in dry-run mode.
    Expected: Commands run as documented without missing steps.
    Evidence: .sisyphus/evidence/task-8-docs.txt

  Scenario: Failure/edge case - misconfiguration troubleshooting
    Tool: Bash
    Steps: Follow docs with missing X_BEARER_TOKEN.
    Expected: Docs lead to deterministic diagnosis and recovery action.
    Evidence: .sisyphus/evidence/task-8-docs-error.txt
  ```

  **Commit**: YES | Message: `docs(ops): add room sync and backfill runbook` | Files: `docs/deployment.md`, `README.md`

## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [ ] F1. Plan Compliance Audit — oracle
- [ ] F2. Code Quality Review — unspecified-high
- [ ] F3. Real Manual QA — unspecified-high (+ playwright if UI)
- [ ] F4. Scope Fidelity Check — deep

## Commit Strategy
- Commit 1: `feat(collab): enforce idempotent tweet room identity`
- Commit 2: `feat(sync): add periodic room sync worker and fallback enqueue`
- Commit 3: `feat(tasks): add resumable backfill and one-shot sync tasks`
- Commit 4: `test(sync): cover idempotency backfill and failure modes`

## Success Criteria
- New X posts appear as new `/rooms/:post_id` entries without user visit dependency.
- Existing historical posts can be backfilled safely and resumed after interruption.
- Running sync repeatedly does not create duplicate rooms or inconsistent snapshots.
- Failure modes are observable via logs/telemetry and bounded by retries/locks.
