#!/usr/bin/env bash
set -euo pipefail

cd /root/task

echo "Starting local payments edge stack..."
docker compose up -d --build

echo "Waiting for Nginx edge to become reachable..."
ready=0
for i in {1..40}; do
  if curl -fsS -H 'Host: api.payments.local' http://localhost:8080/healthz >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done

if [ "$ready" -ne 1 ]; then
  echo "Nginx edge did not become ready in time" >&2
  docker compose ps >&2
  docker compose logs nginx >&2
  exit 1
fi

echo "Validating Nginx configuration inside the running container..."
docker compose exec -T nginx nginx -t

echo "Running smoke checks against the starter environment..."
# Health (no upstream)
curl -fsS -H 'Host: api.payments.local' http://localhost:8080/healthz >/dev/null
# API calls (upstream)
curl -fsS -H 'Host: api.payments.local' http://localhost:8080/v1/charges >/dev/null
curl -fsS -H 'Host: api.payments.local' http://localhost:8080/v1/refunds >/dev/null
# Static asset
curl -fsS -H 'Host: api.payments.local' http://localhost:8080/assets/app.js >/dev/null

echo "Starter stack is running and loadable."

cat <<'EOF'

Validation / change management (Nginx inside Docker Compose)
---------------------------------------------------------------
1) Validate configuration (recommended before reload):
   docker compose exec -T nginx nginx -t

2) Reload Nginx without restarting the container (hot reload):
   docker compose exec -T nginx nginx -s reload

3) Roll back:
   - If you hot-reloaded successfully but need to revert behavior:
     * restore the previous nginx/ config files on disk
     * run: docker compose exec -T nginx nginx -t
     * run: docker compose exec -T nginx nginx -s reload

   - If the container was rebuilt from updated configs:
     * run: docker compose build nginx
     * run: docker compose up -d --no-deps --force-recreate nginx

4) Observe what changed:
   - API request logs:
     docker compose logs --tail=200 nginx
   - Nginx logs are written under /var/log/nginx inside the container.

EOF
