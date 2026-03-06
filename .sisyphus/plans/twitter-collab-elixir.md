# Twitter/X "Today Post" Realtime Collaboration (Elixir Phoenix)

## TL;DR
> **Summary**: Build a Phoenix LiveView app where a single "today" room centers on a specific X post (shown via official embed) plus an in-app text snapshot used for highlight/comment anchors; all interactions sync in realtime.
> **Deliverables**: Phoenix app + Postgres schema; realtime cursors (Presence); highlight-on-selection; anchored comments; hearts; basic moderation/takedown; Playwright E2E.
> **Effort**: Medium
> **Parallel**: YES - 3 waves
> **Critical Path**: Phoenix init → DB schema → LiveView room UX → realtime events/presence → E2E verification

## Context
### Original Request
- Show posts from a favorite Twitter/X account; people join and discuss.
- Realtime shared cursors, text highlighting, hearts, and comments anchored to selected words/phrases.
- Prefer "no server" but also want Elixir.

### Interview Summary
- Priority: **Elixir first** (accept a minimal server).
- X content display: **Embed/OEmbed** (no X API, no scraping).
- To support highlighting, we cannot interact with embed iframe DOM; we will render a **user/admin-provided text snapshot** in-app as the highlight/comment surface, and show the official embed as a reference.

### Metis Review (gaps addressed)
- Add explicit normalization/indexing strategy (emoji-safe); anchors use quote+context selectors (not offsets only).
- Add compliance UI/ops: labeling, ToS link, takedown workflow, audit fields.
- Add security baseline: sanitize all user content, CSP for X scripts, rate limiting.
- Define overlap/highlight policies and room "today" semantics.

### Oracle Review (gaps addressed)
- Snapshot is immutable + versioned; annotations reference `snapshot_version`.
- Embed remains the official source; snapshot is clearly labeled as user-provided quote material.

## Work Objectives
### Core Objective
Deliver an MVP collaborative room around a single daily X post with realtime presence + anchored discussion, without scraping or X API usage.

### Deliverables
- Phoenix (>= 1.7) project with LiveView UI.
- Postgres persistence for posts/snapshots, highlights, comments, and hearts.
- Realtime:
  - Presence/cursors: Phoenix Presence (ephemeral).
  - Highlights/comments/hearts: PubSub broadcast + DB persistence.
- Compliance:
  - Visible link to the original X post.
  - Visible link to X ToS (`https://x.com/tos`).
  - Snapshot labeled "User-provided snapshot".
  - Admin takedown/hide.
- Verification:
  - `mix test` covers contexts + anchor resolution.
  - Playwright E2E covers multi-user realtime behavior.

### Definition of Done (verifiable)
- `mix test` passes.
- `mix ecto.migrate` succeeds on a fresh DB.
- Playwright E2E passes: 2 browsers see each other's cursor; highlight creation replicates; anchored comment replicates; heart count replicates; refresh preserves persisted items.
- Room page still loads when X embed fails (shows tweet link + snapshot + discussion).

### Must Have
- No scraping (no DOM extraction from embed; no headless browsing to fetch tweets).
- Snapshot text is plain text, normalized, immutable, and versioned.
- Anchors use quote+context selectors + position fallback.

### Must NOT Have
- No X API keys or proxying X API.
- No storing arbitrary embed HTML from users (avoid XSS); embed rendering is templated.
- No editable document content (snapshot stays immutable; edits = new version).
- No complex CRDT/Yjs in MVP.

## Verification Strategy
> ZERO HUMAN INTERVENTION — all verification is agent-executed.
- Tests-after using ExUnit + Playwright.
- Evidence per task under `.sisyphus/evidence/`.

## Execution Strategy
### Parallel Execution Waves
Wave 1 (foundation): Phoenix init + DB schema + security/CSP baseline + Playwright harness.
Wave 2 (core UX): room LiveView (embed + snapshot) + realtime presence/cursors + highlight/comment/heart flows.
Wave 3 (ops polish): admin create/takedown + rate limiting + edge-case hardening + final verification.

### Dependency Matrix
- Wave 1 blocks everything.
- Wave 2 blocks Wave 3 final verification.

## TODOs
> Implementation + tests = ONE task.

- [x] 1. Initialize Phoenix LiveView App + Local Dev Setup

  **What to do**: Create a new Phoenix (>= 1.7) project in the workspace root with LiveView + Postgres; ensure `mix phx.server` runs and the default page loads.
  **Must NOT do**: Add custom business logic or UI beyond a smoke-test route.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: greenfield scaffolding + deterministic commands
  - Skills: []

  **Parallelization**: Can Parallel: NO | Wave 1 | Blocks: 2-15 | Blocked By: none

  **References**:
  - External: https://hexdocs.pm/phoenix/installation.html — Phoenix install
  - External: https://hexdocs.pm/phoenix_live_view — LiveView

  **Acceptance Criteria**:
  - [ ] `mix deps.get` succeeds
  - [ ] `mix ecto.create` succeeds
  - [ ] `mix phx.server` serves a page at `http://localhost:4000/`

  **QA Scenarios**:
  ```
  Scenario: Boot app locally
    Tool: Bash
    Steps: mix ecto.create && mix phx.server
    Expected: HTTP 200 for / and no crash in logs
    Evidence: .sisyphus/evidence/task-1-boot.txt

  Scenario: Fresh DB migration path exists
    Tool: Bash
    Steps: mix ecto.drop && mix ecto.create && mix ecto.migrate
    Expected: Commands succeed end-to-end
    Evidence: .sisyphus/evidence/task-1-db.txt
  ```

- [x] 2. Add Baseline Security Headers + CSP for X Embed

  **What to do**: Add security headers (CSP, frame/script sources) so the X embed script can load; keep the policy as strict as possible; document any required allowlists.
  **Must NOT do**: Allow `unsafe-inline` scripts; render arbitrary HTML from user input.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: web security + Phoenix endpoint config
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 7 | Blocked By: 1

  **References**:
  - External: https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP — CSP basics
  - External: https://developer.x.com/en/docs/x-for-websites/javascript-api/overview — widgets.js embed

  **Acceptance Criteria**:
  - [ ] Page still loads without CSP violations for X embed sources (in browser console)
  - [ ] Snapshot/comments remain rendered as escaped text (no HTML execution)

  **QA Scenarios**:
  ```
  Scenario: CSP allows X embed
    Tool: Playwright
    Steps: Open /rooms/today with a seeded post; wait for embed container to render
    Expected: No CSP errors; embed area shows either tweet or fallback link
    Evidence: .sisyphus/evidence/task-2-csp.png

  Scenario: XSS attempt in snapshot is escaped
    Tool: Playwright
    Steps: Create post snapshot containing <script>alert(1)</script>; open /rooms/today
    Expected: Literal text is shown; no dialog; no script executes
    Evidence: .sisyphus/evidence/task-2-xss.png
  ```

- [x] 3. Database Schema: Posts, Snapshots, Highlights, Comments, Hearts, Reports

  **What to do**: Implement Ecto schemas + migrations for:
  - `posts` (one per date, Asia/Seoul timezone semantics)
  - `post_snapshots` (immutable, versioned, normalized plain text)
  - `highlights` (selectors + non-overlap constraints per snapshot)
  - `comments` (anchored to highlight; soft delete)
  - `post_hearts` (toggle per session; unique constraint)
  - `reports` (user report/takedown signal; optional but included for MVP ops)

  **Must NOT do**: Store raw embed HTML; store X API tokens.

  **Recommended Agent Profile**:
  - Category: `quick` — Reason: straightforward schema/migration work
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 6-12 | Blocked By: 1

  **References**:
  - External: https://hexdocs.pm/ecto/Ecto.Migration.html — migrations

  **Acceptance Criteria**:
  - [ ] `mix ecto.migrate` succeeds
  - [ ] Schema has unique index enforcing one post per `room_date`
  - [ ] Schema has unique index enforcing one heart per `(post_id, session_id)`

  **QA Scenarios**:
  ```
  Scenario: Fresh migration
    Tool: Bash
    Steps: mix ecto.drop && mix ecto.create && mix ecto.migrate
    Expected: 0 errors
    Evidence: .sisyphus/evidence/task-3-migrate.txt

  Scenario: Heart uniqueness enforced
    Tool: Bash
    Steps: Run ExUnit test that inserts duplicate heart for same session
    Expected: Second insert fails with constraint error
    Evidence: .sisyphus/evidence/task-3-unique.txt
  ```

- [x] 4. Text Normalization + Anchor Resolution Module (Unicode-safe)

  **What to do**: Create a module that:
  - Normalizes snapshot text on ingest: `\r\n` → `\n`, trim trailing spaces per line, Unicode NFC.
  - Defines anchors using W3C-like selectors:
    - Primary: `quote_exact`, `quote_prefix`, `quote_suffix`
    - Fallback: `start_g`, `end_g` (grapheme indices, 0-based)
  - Resolves anchors to a stable `{start_g, end_g}` even with repeated substrings (use prefix/suffix to disambiguate).
  - Rejects ambiguous matches.

  **Must NOT do**: Use byte offsets; assume ASCII-only.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: tricky Unicode + edge cases + tests
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 1 | Blocks: 9-10 | Blocked By: 3

  **References**:
  - External: https://www.w3.org/TR/annotation-model/#text-quote-selector — TextQuoteSelector
  - External: https://www.w3.org/TR/annotation-model/#text-position-selector — TextPositionSelector
  - External: https://hexdocs.pm/elixir/String.html — graphemes

  **Acceptance Criteria**:
  - [ ] ExUnit covers: emojis, repeated substring disambiguation, newline normalization, ambiguous selection rejection
  - [ ] Given a snapshot with emoji, resolved slice equals `quote_exact`

  **QA Scenarios**:
  ```
  Scenario: Emoji anchor roundtrip
    Tool: Bash
    Steps: mix test test/matdori/text_anchors_test.exs
    Expected: Tests assert correct grapheme indices around emoji
    Evidence: .sisyphus/evidence/task-4-tests.txt

  Scenario: Ambiguous repeated quote
    Tool: Bash
    Steps: mix test with snapshot containing repeated word; selector with short prefix/suffix
    Expected: Resolver returns {:error, :ambiguous}
    Evidence: .sisyphus/evidence/task-4-ambiguous.txt
  ```

- [x] 5. Anonymous Identity + Privacy Disclosure

  **What to do**: Add anonymous user identity:
  - On first visit, generate `session_id` (UUID) + `display_name` + `color` and store in session cookie.
  - Display a short disclosure: cursors and actions are shared live; no personal data required.
  - Allow user to change display name locally (session-scoped).

  **Must NOT do**: Require OAuth/login in MVP.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: auth/session UX and policy text
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 7-11 | Blocked By: 1

  **References**:
  - External: https://hexdocs.pm/plug/Plug.Session.html — session cookies

  **Acceptance Criteria**:
  - [ ] First page load assigns identity and persists across refresh
  - [ ] Two browsers show different names/colors

  **QA Scenarios**:
  ```
  Scenario: Identity persists
    Tool: Playwright
    Steps: Open /rooms/today; refresh; read rendered name/color
    Expected: Same identity after refresh
    Evidence: .sisyphus/evidence/task-5-identity.png

  Scenario: Two users differ
    Tool: Playwright
    Steps: Open two isolated contexts to /rooms/today
    Expected: Names/colors differ
    Evidence: .sisyphus/evidence/task-5-two-users.png
  ```

- [x] 6. Admin "Today Post" Create/Override + Takedown (Token-gated)

  **What to do**: Implement an admin flow protected by `ADMIN_TOKEN` env var:
  - Admin page to set today's `tweet_url` and paste `snapshot_text`.
  - Snapshot is normalized and saved as a new immutable version; post points to current snapshot.
  - Room UI supports selecting a snapshot version (history dropdown); default is the current snapshot.
  - Admin takedown hides embed + snapshot + interactions but keeps audit trail.

  **Assumptions (applied)**:
  - "Today" uses `Asia/Seoul` timezone.
  - Only 1 active post per date.

  **Must NOT do**: Accept arbitrary HTML; store embed HTML.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: admin gating + DB semantics + takedown behavior
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 7 | Blocked By: 3

  **References**:
  - External: https://hexdocs.pm/phoenix_live_view/security-model.html — LiveView security

  **Acceptance Criteria**:
  - [ ] Admin can create today post and it becomes visible on `/rooms/today`
  - [ ] Takedown switches room to "Content unavailable" state

  **QA Scenarios**:
  ```
  Scenario: Create today post
    Tool: Playwright
    Steps: Visit /admin/today; enter ADMIN_TOKEN; set tweet_url + snapshot; save; open /rooms/today
    Expected: Room shows tweet link + snapshot label + empty highlights/comments state
    Evidence: .sisyphus/evidence/task-6-create.png

  Scenario: Takedown
    Tool: Playwright
    Steps: Admin clicks takedown; open /rooms/today in fresh context
    Expected: "Content unavailable"; embed not rendered; actions disabled
    Evidence: .sisyphus/evidence/task-6-takedown.png
  ```

- [x] 7. Room LiveView: Embed Reference + Snapshot Surface + Compliance Labels

  **What to do**: Build `/rooms/today` LiveView:
  - Top: tweet link + official embed container (templated blockquote + widgets.js).
  - Snapshot panel: render normalized snapshot as plain text and label "User-provided snapshot".
  - Snapshot version dropdown: switch the displayed snapshot and load highlights/comments for that snapshot only.
  - Footer: link to `https://x.com/tos`.
  - If embed script fails, show fallback message + link only.
  - If no post exists yet: show empty-state with admin hint (not the admin token).

  **Must NOT do**: Attempt to overlay/select inside the embed iframe.

  **Recommended Agent Profile**:
  - Category: `visual-engineering` — Reason: deliberate layout + readable snapshot UI
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 8-11 | Blocked By: 5,6

  **References**:
  - External: https://developer.x.com/en/docs/x-for-websites/javascript-api/overview — embed snippet

  **Acceptance Criteria**:
  - [ ] Page renders tweet link, snapshot label, and X ToS link
  - [ ] Snapshot is selectable text

  **QA Scenarios**:
  ```
  Scenario: Compliance elements visible
    Tool: Playwright
    Steps: Open /rooms/today
    Expected: "User-provided snapshot" label + link to tweet_url + link to https://x.com/tos
    Evidence: .sisyphus/evidence/task-7-compliance.png

  Scenario: No post empty state
    Tool: Playwright
    Steps: Clear DB; open /rooms/today
    Expected: Empty state message; no crash
    Evidence: .sisyphus/evidence/task-7-empty.png
  ```

- [x] 8. Realtime Presence + Live Cursors (Phoenix Presence)

  **What to do**: Add presence tracking per room:
  - Track each `session_id` when user joins; meta includes `display_name`, `color`, and `cursor` (x,y).
  - Client sends cursor updates (throttled) via LiveView event; server updates presence meta.
  - Render other users' cursors with name badges.

  **Must NOT do**: Persist cursor positions in DB.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: presence diff handling + performance throttling
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 14 | Blocked By: 7

  **References**:
  - External: https://hexdocs.pm/phoenix/Phoenix.Presence.html — Presence

  **Acceptance Criteria**:
  - [ ] Two browsers in same room see each other's cursors within 250ms
  - [ ] Cursor updates are throttled (no more than 20 updates/sec per user)

  **QA Scenarios**:
  ```
  Scenario: Multi-user cursors
    Tool: Playwright
    Steps: Open two contexts; move mouse in snapshot area in context A
    Expected: Context B shows a cursor marker labeled with A's name
    Evidence: .sisyphus/evidence/task-8-cursors.mp4

  Scenario: Throttle enforced
    Tool: Bash
    Steps: Add ExUnit test for throttle function; or log counter under test
    Expected: Rate limiting prevents excessive presence meta updates
    Evidence: .sisyphus/evidence/task-8-throttle.txt
  ```

- [x] 9. Highlight Creation on Selection (Non-overlapping Policy)

  **What to do**: Implement highlight creation on selecting text in the snapshot:
  - JS hook reads selection, computes selectors (exact/prefix/suffix) and grapheme indices using `Intl.Segmenter`.
  - Server resolves anchor (Task 4), enforces non-overlap, stores highlight, and broadcasts.
  - UI renders highlight spans; clicking a highlight focuses its comments.

  **Assumptions (applied)**:
  - Overlapping highlights are rejected with a clear message.

  **Must NOT do**: Try to highlight inside the X embed.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: DOM selection → Unicode indices → persistence
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 10-11 | Blocked By: 4,7

  **References**:
  - External: https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Intl/Segmenter — grapheme segmentation

  **Acceptance Criteria**:
  - [ ] Creating a highlight shows up for all connected users in realtime
  - [ ] Refresh keeps the highlight (loaded from DB)
  - [ ] Selections containing emoji highlight correctly

  **QA Scenarios**:
  ```
  Scenario: Highlight sync
    Tool: Playwright
    Steps: Two contexts open; context A selects a phrase and creates highlight
    Expected: Context B renders highlight within 250ms
    Evidence: .sisyphus/evidence/task-9-highlight.png

  Scenario: Overlap rejected
    Tool: Playwright
    Steps: Create highlight; attempt second highlight overlapping range
    Expected: Error toast/message; second highlight not created
    Evidence: .sisyphus/evidence/task-9-overlap.png
  ```

- [x] 10. Anchored Comments (Comment on Selected Word/Phrase)

  **What to do**: Implement comments anchored to a highlight:
  - Create comment from the selected/highlighted range (stores selectors + highlight_id).
  - Realtime broadcast new comment; render in sidebar ordered by time.
  - Soft delete own comments within 5 minutes (session match) as a minimal abuse control.

  **Must NOT do**: Add full threads/mentions in MVP.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: realtime + permissions + UI states
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 14 | Blocked By: 9

  **References**:
  - External: https://hexdocs.pm/phoenix_live_view/js-interop.html — LiveView hooks

  **Acceptance Criteria**:
  - [ ] Comment appears for all users in realtime and persists on refresh
  - [ ] Only the author session can delete within the allowed window

  **QA Scenarios**:
  ```
  Scenario: Comment sync
    Tool: Playwright
    Steps: Two contexts; create highlight; add comment in context A
    Expected: Context B sees the comment anchored to that highlight
    Evidence: .sisyphus/evidence/task-10-comment.png

  Scenario: Unauthorized delete blocked
    Tool: Playwright
    Steps: Context B attempts to delete context A's comment
    Expected: Delete action hidden or returns error; comment remains
    Evidence: .sisyphus/evidence/task-10-delete.png
  ```

- [x] 11. Hearts (Per Post) + Realtime Count

  **What to do**: Add a heart button for the post:
  - Toggle per `session_id` (unique constraint) and show live count.
  - Broadcast count changes to all users.
  - Rate limit toggles to prevent spam.

  **Must NOT do**: Add per-highlight reactions in MVP.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: small feature but touches DB + realtime
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 2 | Blocks: 14 | Blocked By: 7,3

  **Acceptance Criteria**:
  - [ ] Heart toggle updates count across two clients in realtime
  - [ ] Same session cannot create duplicate hearts

  **QA Scenarios**:
  ```
  Scenario: Heart sync
    Tool: Playwright
    Steps: Two contexts; click heart in context A
    Expected: Context B count increments within 250ms
    Evidence: .sisyphus/evidence/task-11-heart.png

  Scenario: Duplicate prevented
    Tool: Bash
    Steps: mix test covering unique constraint + toggle semantics
    Expected: No duplicate rows created
    Evidence: .sisyphus/evidence/task-11-unique.txt
  ```

- [x] 12. Reports + Admin Review (Minimal Moderation)

  **What to do**: Add a "Report" button for the room that creates a `reports` record with reason; admin page lists reports and offers takedown.
  **Must NOT do**: Build a full moderation suite.

  **Recommended Agent Profile**:
  - Category: `unspecified-low` — Reason: straightforward CRUD + admin view
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: 14 | Blocked By: 6,7

  **Acceptance Criteria**:
  - [ ] Report creates a DB row and shows a confirmation
  - [ ] Admin can view reports list

  **QA Scenarios**:
  ```
  Scenario: Report flow
    Tool: Playwright
    Steps: On /rooms/today click Report; pick reason; submit
    Expected: Confirmation shown; admin sees report in /admin/reports
    Evidence: .sisyphus/evidence/task-12-report.png

  Scenario: Rate limit reporting
    Tool: Bash
    Steps: ExUnit test for report rate limit per session
    Expected: Returns error after threshold
    Evidence: .sisyphus/evidence/task-12-rl.txt
  ```

- [x] 13. Rate Limiting + Abuse Controls (LiveView Events)

  **What to do**: Implement per-session throttles:
  - Cursor updates: server-side guard + client debounce.
  - Highlights/comments/hearts/reports: limits per minute with clear error messages.
  - Use ETS-based counters for MVP (no external dependency) unless Phoenix version makes PlugAttack straightforward.

  **Must NOT do**: Add Redis or distributed rate limiting in MVP.

  **Recommended Agent Profile**:
  - Category: `deep` — Reason: correctness + user experience under load
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: 14 | Blocked By: 8-12

  **Acceptance Criteria**:
  - [ ] ExUnit verifies throttles return stable error codes
  - [ ] Playwright shows user-friendly error for rate-limited actions

  **QA Scenarios**:
  ```
  Scenario: Comment spam throttled
    Tool: Playwright
    Steps: Attempt to post >N comments quickly
    Expected: After N, UI shows rate-limit message; no DB inserts beyond limit
    Evidence: .sisyphus/evidence/task-13-rl.png

  Scenario: Cursor flood guarded
    Tool: Bash
    Steps: ExUnit test on cursor throttling function
    Expected: Update calls beyond threshold are ignored
    Evidence: .sisyphus/evidence/task-13-cursor.txt
  ```

- [x] 14. Playwright E2E Harness (Multi-user Realtime)

  **What to do**: Add Playwright to the project (likely under `assets/`), with tests that:
  - Seed a today post (admin flow or direct DB seed helper).
  - Spawn 2 isolated contexts.
  - Verify realtime cursor, highlight, comment, and heart sync.
  - Verify refresh persistence.

  **Must NOT do**: Rely on manual verification.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: E2E harness + flake resistance
  - Skills: [`playwright`] — stable browser automation

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: 15 | Blocked By: 6-11

  **References**:
  - External: https://playwright.dev/docs/intro — Playwright

  **Acceptance Criteria**:
  - [ ] `npx playwright test` passes locally
  - [ ] Tests run headless by default and produce artifacts on failure

  **QA Scenarios**:
  ```
  Scenario: Full multi-user realtime E2E
    Tool: Playwright
    Steps: Run test suite
    Expected: All assertions pass; video/screenshot collected on failure
    Evidence: .sisyphus/evidence/task-14-e2e.txt

  Scenario: Embed failure fallback
    Tool: Playwright
    Steps: Block requests to platform.twitter.com; open /rooms/today
    Expected: Fallback link visible; rest of room works
    Evidence: .sisyphus/evidence/task-14-embed-fallback.png
  ```

- [ ] 15. Hardening Pass: Anchor Edge Cases + UI Polish

  **What to do**: Address known edge cases from Metis/Oracle:
  - Multiple identical substrings (ensure prefix/suffix length sufficient; show an "ambiguous" error if not).
  - Selection trimming rules (strip leading/trailing whitespace before anchor creation).
  - Snapshot versioning: old highlights/comments remain tied to the snapshot they were created on.
  - Version UX decision (fixed): default to current snapshot; allow viewing older versions via dropdown; do not merge annotations across versions.
  - Ensure embed and snapshot clearly separated; no confusion about source.

  **Must NOT do**: Add editable snapshots.

  **Recommended Agent Profile**:
  - Category: `unspecified-high` — Reason: cross-cutting polish + correctness
  - Skills: []

  **Parallelization**: Can Parallel: NO | Wave 3 | Blocks: F1-F4 | Blocked By: 9-14

  **Acceptance Criteria**:
  - [ ] Playwright includes at least one emoji selection test and one ambiguous selection test
  - [ ] Room UI contains clear source labels and still works without embed

  **QA Scenarios**:
  ```
  Scenario: Ambiguous selection UX
    Tool: Playwright
    Steps: Attempt highlight on a repeated substring with insufficient context
    Expected: UI shows "selection is ambiguous"; no highlight saved
    Evidence: .sisyphus/evidence/task-15-ambiguous.png

  Scenario: Snapshot version retains old anchors
    Tool: Playwright
    Steps: Create highlight/comment; create new snapshot version as admin; open room
    Expected: Old annotations are shown under the old snapshot view or clearly hidden with a notice
    Evidence: .sisyphus/evidence/task-15-version.png
  ```

- [x] 16. Deployment Notes (Fly.io) + Production Config (Optional)

  **What to do**: Provide production-ready config notes:
  - `DATABASE_URL`, `SECRET_KEY_BASE`, `ADMIN_TOKEN`.
  - WebSocket configuration and proxy notes.
  - Fly.io deploy steps (optional but included).

  **Must NOT do**: Hardcode secrets in repo.

  **Recommended Agent Profile**:
  - Category: `writing` — Reason: concise ops docs
  - Skills: []

  **Parallelization**: Can Parallel: YES | Wave 3 | Blocks: none | Blocked By: 1

  **References**:
  - External: https://fly.io/docs/elixir/getting-started/ — Phoenix on Fly

  **Acceptance Criteria**:
  - [ ] A deploy doc exists and does not include any real secrets

  **QA Scenarios**:
  ```
  Scenario: Production config sanity
    Tool: Bash
    Steps: mix release (or mix phx.gen.release) in CI-like environment
    Expected: Release builds without missing env vars (except runtime-provided)
    Evidence: .sisyphus/evidence/task-16-release.txt
  ```

## Final Verification Wave (4 parallel agents, ALL must APPROVE)
- [x] F1. Plan Compliance Audit — oracle
- [x] F2. Code Quality Review — unspecified-high
- [x] F3. Real Manual QA (agent-executed) — unspecified-high (+ playwright)
- [x] F4. Scope Fidelity Check — deep

## Commit Strategy
- Commit 1: `chore(phx): initialize phoenix liveview app`
- Commit 2: `feat(db): add posts highlights comments reactions schema`
- Commit 3: `feat(room): realtime presence highlights comments hearts`
- Commit 4: `feat(admin): create today post + takedown + rate limits`
- Commit 5: `test(e2e): add playwright multi-user realtime coverage`

## Success Criteria
- A new visitor can join `/rooms/today`, see the X embed reference, and interact on the snapshot with others in realtime.
- Highlights/comments/hearts persist after refresh.
- Basic abuse and takedown controls exist.
