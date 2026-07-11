# Payments Nginx Edge Improvements (Local Docker Compose)

This repo improves the Nginx edge-tier reliability and observability without changing the architecture (still Docker Compose + Nginx proxying to 3 upstream pods).

## What changed

### 1) Resilient upstream handling for `/v1`
- `nginx/conf.d/site.conf`
  - Expanded the `upstream payments_api` with:
    - `zone payments_api 64k` for shared passive health state
    - `keepalive 32` to avoid reconnect storms during churn
    - `least_conn` balancing
    - Passive health parameters: `max_fails=3 fail_timeout=10s`
  - Added controlled retry behavior:
    - Generic `/v1/` location retries on `error timeout http_502 http_503 http_504` (max 3 upstreams, capped total retry window).
    - Payment-changing endpoints are configured conservatively:
      - `location = /v1/charges` and `location = /v1/refunds` set `proxy_next_upstream off` (no automatic retries) to avoid unintended duplicate side effects.

### 2) Clear access logging for upstream selection and latency origin
- `nginx/snippets/logging.conf`
  - Updated `edge_main` log format to include:
    - selected upstream: `$upstream_addr`
    - upstream status: `$upstream_status`
    - edge vs upstream timing:
      - `$request_time` (total edge duration)
      - `$upstream_connect_time`
      - `$upstream_response_time`

- `nginx/conf.d/site.conf`
  - Ensures a single payments-focused access log at `/var/log/nginx/payments_access.log`.

### 3) Hardened proxy headers + payments-safe caching
- `nginx/snippets/shared.conf`
  - Improved forwarding headers (`X-Forwarded-For` uses `$proxy_add_x_forwarded_for`)
  - Added keepalive-friendly connection hygiene.

- `nginx/snippets/api-policy.conf`
  - Explicitly disables edge caching for API proxying.
  - Hides unsafe cache validators/headers from upstream.

### 4) Static assets served efficiently
- `nginx/conf.d/site.conf` + `nginx/snippets/static-policy.conf`
  - `/assets/` uses `try_files` and a strong cache policy:
    - `Cache-Control: public, max-age=31536000, immutable`
    - `expires 1y`
  - `/assets/` access logs are disabled to keep API logs focused.

### 5) Basic abuse controls and secure edge defaults
- `nginx/nginx.conf`
  - Added `limit_req_zone` and `limit_conn_zone` keyed by `$binary_remote_addr`.
- `nginx/conf.d/site.conf`
  - Applies rate limiting and connection limits to the server.
  - Exempts `/healthz` from abuse limits.
- `nginx/snippets/security-headers.conf`
  - Adds modern security headers for the static page and baseline protections.

## How to validate

1) Start stack:
   docker compose up -d --build

2) Validate Nginx config:
   docker compose exec -T nginx nginx -t

3) Smoke checks:
   curl -fsS -H 'Host: api.payments.local' http://localhost:8080/healthz
   curl -fsS -H 'Host: api.payments.local' http://localhost:8080/v1/charges
   curl -fsS -H 'Host: api.payments.local' http://localhost:8080/v1/refunds
   curl -fsS -H 'Host: api.payments.local' http://localhost:8080/assets/app.js

4) Observe latency origin and upstream selection:
   - Look at `/var/log/nginx/payments_access.log` (or `docker compose logs nginx`)
   - Each API log line includes upstream addr and both edge and upstream timings.

## How to reload / rollback safely

### Reload (hot)
1) Validate:
   docker compose exec -T nginx nginx -t
2) Reload:
   docker compose exec -T nginx nginx -s reload

### Roll back
- Restore previous config files on disk, validate again, then reload:
  docker compose exec -T nginx nginx -t
  docker compose exec -T nginx nginx -s reload

- If you prefer rebuild/replace (configs are baked into the image in this kata):
  docker compose build nginx
  docker compose up -d --no-deps --force-recreate nginx
