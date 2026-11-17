# hq

Self-hosted tool stack. One subfolder per tool, each its own independent
`docker-compose.yml` — no top-level compose file or orchestration here; a
reverse proxy and shared Docker network are managed outside this repo, at
the host/Portainer level.

## Tools

| Folder | Tool | What it is |
|---|---|---|
| `hermes/` | [Hermes Agent](https://github.com/NousResearch/hermes-agent) | The agent gateway running this repo's own assistant. |
| `grafana/` | Grafana + Loki | Dashboards and log aggregation. |
| `postgres/` | Postgres + pgAdmin | **Shared** database instance — see below. |
| `jenkins/` | Jenkins agent installer | Cross-platform agent/node setup scripts (not a compose stack). |
| `paperclip/` | [Paperclip](https://github.com/paperclipai/paperclip) | Orchestrates a team of AI agents running tasks for a company (org chart, budgets, approvals). |
| `hindsight/` | [Hindsight](https://github.com/vectorize-io/hindsight) | Long-term memory engine for AI agents (retain/recall/reflect). |
| `privatebin/` | [PrivateBin](https://github.com/PrivateBin) | Self-hosted, zero-knowledge-encrypted pastebin — our Hastebin alternative. |

## Shared Postgres

`postgres/` is the one shared database instance every other multi-container
tool connects to, rather than each running its own embedded Postgres.
`paperclip/`, `hindsight/`, and `privatebin/` all join its `hq-postgres`
external Docker network and connect to it by the hostname `postgres`, using
a dedicated role + database each (provisioned by
`postgres/init/10-app-databases.sh` — see that file for what to run by hand
if the instance already existed before this was added).

**Bring `postgres/` up first** (or at least once) before any of the above —
their init SQL depends on it, and the `hq-postgres` network has to exist for
them to join it.

To add a new multi-container tool, follow this pattern rather than giving it
its own embedded database: join `hq-postgres`, add its role/db to
`postgres/init/10-app-databases.sh`, and connect via hostname `postgres`.

## Compose conventions

- `expose:`, never `ports:` — the external proxy handles host exposure.
- `${VAR:-default}` for anything safe to default; `${VAR:?message}` for
  anything that must never silently default (secrets, keys).
- Every service gets a `healthcheck:` and `restart: unless-stopped`.
- Named volumes, never bind-mounted host paths (except read-only config
  files like `privatebin/conf.php`).
