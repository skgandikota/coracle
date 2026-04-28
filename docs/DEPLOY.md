# Deploying the orchestrator with Docker

The orchestrator ships two production images:

| Variant | Dockerfile | Approx. size | When to use |
| --- | --- | --- | --- |
| **slim** (default) | [`Dockerfile`](../Dockerfile) | < 250 MB | Production. No browser. |
| **browser** | [`Dockerfile.browser`](../Dockerfile.browser) | ~600 MB | Opt-in for the browser-fallback search path (#9). Bakes Playwright + Chromium. |

The slim image **does not** install Ollama or any model weights. Run Ollama
as a sibling container and point the orchestrator at it via
`OLLAMA_BASE_URL` (see [`p7-docker-compose`](https://github.com/skgandikota/orchestrator/issues/47)).

---

## Build

```bash
# Slim, production image (default target).
docker build -t orchestrator:slim --target runtime .

# Browser-fallback variant.
docker build -t orchestrator:browser -f Dockerfile.browser .

# Multi-arch (amd64 + arm64) — see issue #48 for the CI matrix.
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/skgandikota/orchestrator:dev \
  --target runtime \
  --push .
```

The `--target=runtime` arg lets CI build only the slim variant without
also producing the (unused) `builder` stage as a final image.

## Run

```bash
docker run --rm \
  --name orchestrator \
  -p 8000:8000 \
  -v $(pwd)/config:/etc/orchestrator:ro \
  -v orchestrator-data:/var/lib/orchestrator \
  -e OLLAMA_BASE_URL=http://ollama:11434 \
  orchestrator:slim
```

Mounts:

- `/etc/orchestrator` — read-only config directory. The default config path
  inside the image is `/etc/orchestrator/config.yaml`.
- `/var/lib/orchestrator` — writable data directory (SQLite cache, logs).

The image runs as the non-root `orchestrator` user (UID 1000); make sure
host-side bind mounts are readable / writable by that UID.

### MCP-stdio mode

`stdio` is not a network protocol, so port 8000 is irrelevant here. Run the
container with `-i` and override the command:

```bash
docker run --rm -i \
  -v $(pwd)/config:/etc/orchestrator:ro \
  orchestrator:slim mcp
```

### CLI one-shots

```bash
docker run --rm \
  -v $(pwd)/config:/etc/orchestrator:ro \
  orchestrator:slim cli mcp list
```

### Browser-fallback (opt-in)

Two ways to get Playwright + Chromium at runtime:

1. **Use the browser image** (simplest, recommended for ephemeral runs):

   ```bash
   docker run --rm -p 8000:8000 orchestrator:browser
   ```

2. **Mount the host's Playwright cache into the slim image** (keeps your
   production image small and shares one browser cache across containers):

   ```bash
   docker run --rm \
     -e PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
     -v $HOME/.cache/ms-playwright:/ms-playwright:ro \
     -p 8000:8000 \
     orchestrator:slim
   ```

## Environment variables

| Variable | Default | Description |
| --- | --- | --- |
| `OLLAMA_BASE_URL` | _unset_ | Base URL of the sibling Ollama container, e.g. `http://ollama:11434`. |
| `ORCHESTRATOR_CONFIG` | `/etc/orchestrator/config.yaml` | Path to the YAML config file inside the container. |
| `ORCHESTRATOR_DATA_DIR` | `/var/lib/orchestrator` | Writable directory for SQLite + logs. |
| `PYTHONUNBUFFERED` | `1` | Stream stdout/stderr without buffering (set in the image). |
| `PYTHONDONTWRITEBYTECODE` | `1` | Disable `.pyc` writes (set in the image). |
| `PLAYWRIGHT_BROWSERS_PATH` | `/opt/playwright` (browser image only) | Where Playwright looks for browser binaries. Override to share a host cache. |

## Healthcheck

The image declares:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl --fail --silent http://localhost:8000/v1/models || exit 1
```

`docker ps` will show `(healthy)` once `/v1/models` returns 200.

## Troubleshooting

### Ollama unreachable

`/v1/models` returns 502 and the orchestrator logs
`connection refused: ollama:11434`.

- Ensure both containers are on the same Docker network.
- Verify `OLLAMA_BASE_URL` matches the sibling service name (in
  `docker compose`, this is the service key, not `localhost`).
- From the orchestrator container: `curl -fsS $OLLAMA_BASE_URL/api/tags`.

### Port 8000 already in use

```
Error: bind: address already in use
```

Pick a different host port: `-p 18000:8000`. The container always listens
on `8000` internally; map it wherever you like on the host.

### Permission denied on volume mounts

The container runs as UID 1000. Bind-mounted host directories must be
readable (and `/var/lib/orchestrator` writable) by that UID:

```bash
sudo chown -R 1000:1000 ./data
```

Named volumes (`-v orchestrator-data:/var/lib/orchestrator`) avoid this
entirely — Docker creates them with the right ownership.

### Image is too large

Confirm you built the slim image with `--target runtime` (not the
`builder` stage), and that `.dockerignore` is in place — a stray
`.venv/` or `tests/` in the build context can balloon the layer cache.

```bash
docker image ls orchestrator:slim --format '{{.Size}}'
```

## Make targets

For local convenience the top-level `Makefile` exposes:

```bash
make docker-build   # build orchestrator:slim
make docker-run     # run orchestrator:slim with sensible defaults
```
