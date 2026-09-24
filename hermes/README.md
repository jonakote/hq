# Hermes deployment

This directory contains the Docker Compose deployment for Hermes Agent on the
VPS. It is designed to be copied to `/hermes` on the VPS.

The official `nousresearch/hermes-agent` image runs the supervised gateway and
the built-in dashboard in one container. Hermes state is persisted in
`/hermes/data`, while the VPS `/workspace` bind mount is shared with VS Code
Remote SSH.

## First-time setup on the VPS

From this directory on the VPS:

```bash
cp .env.example .env
```

Edit `.env` and replace all `CHANGE_ME` values. Generate the API and session
secrets with:

```bash
openssl rand -hex 32
```

Set `HERMES_UID` and `HERMES_GID` to the UID and GID of the Linux user that
owns `/workspace` (`id -u` and `id -g`). Create the shared workspace if it does
not exist yet:

```bash
sudo mkdir -p /workspace
sudo chown "$(id -u):$(id -g)" /workspace
```

Run the official interactive setup wizard once. It stores provider credentials
and Hermes configuration in the persistent `data/` directory:

```bash
docker compose --profile setup run --rm hermes-setup
```

Start the gateway and dashboard:

```bash
docker compose pull
docker compose up -d
docker compose logs -f hermes
```

## Local access

Keep the Compose ports bound to VPS loopback. From the local machine, create an
SSH tunnel:

```bash
ssh -N \
  -L 9119:127.0.0.1:9119 \
  -L 8642:127.0.0.1:8642 \
  user@vps
```

Open `http://127.0.0.1:9119` and sign in with the dashboard credentials from
`.env`. VS Code should connect with Remote SSH and open `/workspace/<project>`;
Hermes uses that same path inside the container.

Useful commands:

```bash
docker compose ps
docker compose logs -f hermes
docker compose exec hermes hermes status
docker compose exec hermes hermes config check
docker compose pull && docker compose up -d
```

## Security and scope

Docker socket access is intentionally not enabled. Mounting
`/var/run/docker.sock` would give Hermes near-root control over the VPS Docker
daemon and could affect Coolify-managed workloads. Add that only after a
separate threat-model review; prefer a narrowly scoped sidecar or API proxy if
Hermes later needs Docker operations.

Do not expose ports `8642` or `9119` publicly without adding a deliberate
firewall/reverse-proxy/authentication design. The Compose file keeps the
official image entrypoint intact so its built-in supervision remains active.
