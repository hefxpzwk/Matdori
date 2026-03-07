# Deployment Notes (Fly.io)

## Required Environment Variables

- `DATABASE_URL` - Postgres connection string
- `SECRET_KEY_BASE` - Phoenix secret key
- `PHX_HOST` - public host name
- `X_BEARER_TOKEN` - X API Bearer token for optional account timeline sync
- `X_SOURCE_USERNAME` - target X account handle (default: `bbiribarabu`, optional)
- `X_PERIODIC_SYNC_ENABLED` - enable periodic background sync (`true`/`false`, default: `false`)
- `X_PERIODIC_SYNC_INTERVAL_MS` - periodic sync interval in milliseconds (default: `60000`, optional)

## Realtime Considerations

- WebSocket endpoint is `/live`.
- If you use a reverse proxy, ensure WebSocket upgrade is enabled.
- Keep sticky sessions off unless your proxy requires them; Presence/PubSub handles fanout.

## Fly.io Quick Start

1. `fly launch`
2. Create or attach Postgres and set `DATABASE_URL`
3. Set secrets:
   - `fly secrets set SECRET_KEY_BASE=...`
   - (optional) `fly secrets set X_BEARER_TOKEN=...`
   - (optional) `fly secrets set X_SOURCE_USERNAME=bbiribarabu`
   - (optional) `fly secrets set X_PERIODIC_SYNC_ENABLED=true`
   - (optional) `fly secrets set X_PERIODIC_SYNC_INTERVAL_MS=60000`
4. Deploy: `fly deploy`
5. Run migrations: `fly ssh console -C "/app/bin/matdori eval 'Matdori.Release.migrate'"`

## Sync Operations

- One-shot sync run:
  - `mix matdori.sync_rooms_once`

- Full backfill dry-run:
  - `mix matdori.backfill_rooms --dry-run --max-posts 50`

- Full backfill resumable run:
  - `mix matdori.backfill_rooms --resume --max-posts 50 --batch-size 50 --sleep-ms 250`

## Health Checks

- Verify home page: `GET /`
- Verify room list page: `GET /rooms`
- Verify room detail page: `GET /rooms/:post_id`
