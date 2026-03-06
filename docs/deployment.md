# Deployment Notes (Fly.io)

## Required Environment Variables

- `DATABASE_URL` - Postgres connection string
- `SECRET_KEY_BASE` - Phoenix secret key
- `PHX_HOST` - public host name
- `ADMIN_TOKEN` - admin access token for `/admin/today` and `/admin/reports`
- `X_BEARER_TOKEN` - X API Bearer token for account timeline sync
- `X_SOURCE_USERNAME` - target X account handle (default: `bbiribarabu`)

## Realtime Considerations

- WebSocket endpoint is `/live`.
- If you use a reverse proxy, ensure WebSocket upgrade is enabled.
- Keep sticky sessions off unless your proxy requires them; Presence/PubSub handles fanout.

## Fly.io Quick Start

1. `fly launch`
2. Create or attach Postgres and set `DATABASE_URL`
3. Set secrets:
   - `fly secrets set SECRET_KEY_BASE=...`
   - `fly secrets set ADMIN_TOKEN=...`
   - `fly secrets set X_BEARER_TOKEN=...`
   - `fly secrets set X_SOURCE_USERNAME=bbiribarabu`
4. Deploy: `fly deploy`
5. Run migrations: `fly ssh console -C "/app/bin/matdori eval 'Matdori.Release.migrate'"`

## Health Checks

- Verify home page: `GET /`
- Verify room page: `GET /rooms/latest`
- Verify admin routes are token-protected by behavior
