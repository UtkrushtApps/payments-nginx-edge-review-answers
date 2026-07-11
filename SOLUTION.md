# Solution Steps

1. Update Nginx core config (nginx/nginx.conf): disable duplicate global access logging, turn off server tokens, add basic rate/connection limiting zones (limit_req_zone/limit_conn_zone) suitable for a payments-facing edge, and keep error logging unchanged.

2. Implement improved structured access logging (nginx/snippets/logging.conf): extend the `edge_main` log_format to include upstream selection ($upstream_addr/$upstream_status) and latency breakdown ($request_time vs $upstream_connect_time/$upstream_response_time).

3. Harden and modularize payments proxy behavior (nginx/snippets/shared.conf + new api snippets): update proxy headers (use $proxy_add_x_forwarded_for, preserve Host/Proto), enable connection hygiene for keepalive, and create API cache-safety defaults that explicitly disable proxy caching for /v1 and hide unsafe cache headers from upstream.

4. Make upstream handling resilient in the edge tier (nginx/conf.d/site.conf): define an upstream with passive health (`max_fails`/`fail_timeout`), enable keepalive and least-connections, and apply controlled retry behavior for the generic `/v1/` location to reduce 502s during upstream disruptions.

5. Keep payment-changing endpoints conservative (nginx/conf.d/site.conf): configure `/v1/charges` and `/v1/refunds` with `proxy_next_upstream off` (no automatic retries) to avoid unintended duplicate side effects; still apply strict no-store caching headers and enhanced upstream visibility response headers.

6. Tune static asset serving (nginx/snippets/static-policy.conf + nginx/conf.d/site.conf): serve `/assets/` using `try_files`, apply strong immutable caching (`max-age=1y`), and disable access logs for assets to keep API logs focused; ensure the `/assets/` location is distinct from `/v1/` proxying.

7. Add basic abuse controls and secure edge defaults (nginx/conf.d/site.conf + nginx/snippets/security-headers.conf): apply limit_req/limit_conn on the server, exempt `/healthz`, deny requests for hidden dotfiles, and add baseline security headers for the static landing page.

8. Document operational change/validation/revert commands (artifacts/edge-nginx-changes.md and run.sh): include `nginx -t`, `nginx -s reload`, and rebuild/force-recreate rollback guidance, plus what each change was intended to fix.

9. Run the provided run.sh smoke test and then manually confirm observability: send a few `/v1/...` requests and verify the access log lines include upstream addr + edge/upstream timing; confirm static assets return the expected immutable cache headers.

