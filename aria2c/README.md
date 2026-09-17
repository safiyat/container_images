# aria2c

OCI-compliant [aria2](https://aria2.github.io/) download daemon with JSON-RPC/XML-RPC enabled and the [webui-aria2](https://github.com/safiyat/webui-aria2) web interface, built and run with [Podman](https://podman.io/). Base image: `ubuntu:noble`.

## Dependencies

- [Podman](https://podman.io/) 4.0+ (uses `crun` as the OCI runtime)
- Network access to pull `docker.io/library/ubuntu:noble`, install apt packages, and fetch the pinned `safiyat/webui-aria2` archive during build
- Ports `6800` (RPC) and `8080` (web UI) free on the host when published

## Build

```sh
podman build -t localhost/aria2c:latest .
```

`webui-aria2` is fetched at the pinned commit `109903f0` from the `safiyat/webui-aria2` repository at build time (override with `--build-arg WEBUI_ARIA2_COMMIT=<sha>`). Its prebuilt `docs/` is served as-is by `node-server.js`, which uses only Node runtime built-ins, so no `npm install` is required.

## Run

A host path must be mounted at `/downloads` and an RPC secret must be supplied (`--rpc-secret=<token>`); the container refuses to start otherwise.

### Required arguments

All of these are enforced by the entrypoint; each is mandatory:

| Requirement              | How to provide                          | Failure                            |
| ------------------------ | --------------------------------------- | ---------------------------------- |
| Download host path       | `-v /absolute/host/path:/downloads`     | `ERROR: /downloads is not mounted.` |
| RPC secret               | `--rpc-secret=<token>` after the image  | `ERROR: --rpc-secret=<token> is required...` |

The container runs as UID 1001, so the host download directory must be writable by that UID (e.g. `chown -R 1001:1001 downloads`).

### Quick start

```sh
mkdir -p "$PWD/downloads"
podman run -d \
  --name aria2c \
  -p 6800:6800 \
  -p 8080:8080 \
  -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest \
  --rpc-secret=changeme
```

Once started:

- Web UI: `http://localhost:8080` (enter `changeme` in the UI's RPC secret field)
- RPC JSON-RPC: `http://localhost:6800/jsonrpc`

### Forwarding ports

Only publish the ports you need:

| Purpose  | Container port | Publish as (example)       |
| -------- | -------------- | -------------------------- |
| Web UI   | 8080           | `-p 8080:8080`             |
| RPC API  | 6800           | `-p 6800:6800`             |
| Both     | 6800 + 8080    | `-p 6800:6800 -p 8080:8080`|

To reach the container from other machines on the LAN, omit the host bind (both ports already listen on all interfaces):

```sh
podman run -d --name aria2c -p 6800:6800 -p 8080:8080 \
  -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest --rpc-secret=changeme
# web UI at http://<host-ip>:8080 , RPC at http://<host-ip>:6800/jsonrpc
```

### Download directory mount

- Must be provided: `-v /absolute/host/path:/downloads`.
- Must be a host path bind mount. Named or anonymous container volumes are rejected:
  `ERROR: /downloads must be mounted from a host directory, not a container volume.`
- Must be writable by UID 1001.

### Persisting config and session

`/home/aria2/.aria2` holds the generated `aria2.conf` and the session file `aria2.session` (saved every 60 seconds). Mount a host path there to persist both across container removal:

```sh
mkdir -p "$PWD/downloads" "$PWD/aria2-config"
podman run -d --name aria2c \
  -p 6800:6800 -p 8080:8080 \
  -v "$PWD/downloads:/downloads" \
  -v "$PWD/aria2-config:/home/aria2/.aria2" \
  localhost/aria2c:latest --rpc-secret=changeme
```

The entrypoint rewrites the config file on every start, so configuration is never stale. If the mount is omitted, an anonymous volume is used (state is lost when the container is removed).

### Notes

- The RPC secret is required for every run: `--rpc-secret=<token>`. The web UI's settings dialog has a matching `secret` field.

## Usage

### Web UI

Open `http://localhost:8080` in a browser. The UI connects to the RPC endpoint at the same host on port `6800` (configurable from the UI's settings dialog). Enter the `--rpc-secret` token in the UI's RPC secret field.

### RPC

The RPC endpoint listens on all interfaces at `http://localhost:6800/jsonrpc` and requires the secret (token auth: `token:<token>`).

```sh
# getVersion
curl -s http://localhost:6800/jsonrpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"aria2.getVersion","params":["token:changeme"]}'

# forward a URI into the download queue
curl -s http://localhost:6800/jsonrpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"aria2.addUri","params":["token:changeme",["https://example.com/file.iso"]]}'
```

In every `params` array, the token comes first (`["token:<token>", ...args]`).

### Configuration options

Pass options to the `podman run` command after the image name. The entrypoint **parses them, validates them, and writes them to `/home/aria2/.aria2/aria2.conf`** in native aria2 config format, then starts `aria2c` with `--conf-path=/home/aria2/.aria2/aria2.conf`. Options are not forwarded to the command line.

`--rpc-secret` is mandatory. All other options are optional; unspecified options keep the tuning defaults shown in the table below.

| Option                        | Config line                 | Valid values                    |
| ----------------------------- | --------------------------- | ------------------------------- |
| `--rpc-secret=<token>`        | `rpc-secret=changeme`       | non-empty token (**required**)  |
| `--continue[=true\|false]`     | `continue=true`             | `true`, `false` (bare = true)   |
| `--file-allocation=<m>`       | `file-allocation=none`      | `none`, `prealloc`, `falloc`    |
| `--max-concurrent-downloads=<n>` | `max-concurrent-downloads=3` | number                        |
| `--max-overall-download-limit=<s>` | `max-overall-download-limit=1M` | size (e.g. `0`, `100K`, `1M`) |
| `--max-connection-per-server=<n>` | `max-connection-per-server=4` | number                       |
| `--min-split-size=<s>`        | `min-split-size=1M`         | size (e.g. `1M`)                |
| `--split=<n>`                 | `split=5`                   | number                          |

Example with all options:

```sh
podman run -d \
  --name aria2c \
  -p 6800:6800 \
  -p 8080:8080 \
  -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest \
    --rpc-secret=changeme \
    --continue \
    --file-allocation=none \
    --max-concurrent-downloads=3 \
    --max-overall-download-limit=1M \
    --max-connection-per-server=4 \
    --min-split-size=1M \
    --split=5
```

The resulting `aria2.conf`:

```ini
enable-rpc=true
rpc-listen-all=true
rpc-listen-port=6800
dir=/downloads
save-session=/home/aria2/.aria2/aria2.session
save-session-interval=60
file-allocation=prealloc
log-level=warn
max-concurrent-downloads=16
max-overall-download-limit=0
max-connection-per-server=16
min-split-size=5M
split=16
rpc-secret=changeme
continue=true
file-allocation=none
max-concurrent-downloads=3
max-overall-download-limit=1M
max-connection-per-server=4
min-split-size=1M
split=5
```

`aria2c` refuses unknown `--` options with a usage error (`ERROR: unsupported option: --...`) and rejects invalid values (`ERROR: invalid value for --split: 'abc'`). Arguments that are not options are treated as download URIs and passed to `aria2c`:

```sh
podman run -d --name aria2c \
  -p 6800:6800 -p 8080:8080 \
  -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest \
    --rpc-secret=changeme \
    https://example.com/file.iso
```

### One-off download (exit when done)

For a single URI without the daemon, override the command to exit after the transfer:

```sh
podman run --rm \
  -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest \
    --rpc-secret=changeme \
    https://example.com/file.iso
```

Note: this still starts the RPC listener and web UI; that is inherent to the fixed entrypoint.

Defaults:

| Setting              | Value                                             |
| -------------------- | ------------------------------------------------- |
| RPC port             | 6800                                              |
| RPC listener         | all interfaces                                    |
| Web UI               | `http://<host>:8080` (node-server.js)             |
| Download dir         | `/downloads` (host path mount, required)          |
| Config file          | `/home/aria2/.aria2/aria2.conf`                   |
| Session file         | `/home/aria2/.aria2/aria2.session` (saved 60s)    |
| User                 | `aria2` (UID 1001, GID 1001), non-root           |

Tuning defaults (overridden by the matching `--option`):

| Setting                  | Config line                       | Default      |
| ------------------------ | --------------------------------- | ------------ |
| File allocation          | `file-allocation=prealloc`        | `prealloc`   |
| Log level                | `log-level=warn`                  | `warn`       |
| Max concurrent downloads | `max-concurrent-downloads=16`     | `16`         |
| Max overall down limit   | `max-overall-download-limit=0` (unlimited) | `0` |
| Max connections/server   | `max-connection-per-server=16`    | `16`         |
| Min split size           | `min-split-size=5M`               | `5M`         |
| Split count              | `split=16`                        | `16`         |

## Development

Iterate on the image and verify the parsed configuration and both servers:

```sh
podman build -t localhost/aria2c:latest .
mkdir -p "$PWD/downloads"
podman run -d --name aria2c-dev \
  -p 6800:6800 \
  -p 8080:8080 \
  -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest --continue --split=4 --rpc-secret=dev
podman exec aria2c-dev cat /home/aria2/.aria2/aria2.conf
curl -s -o /dev/null -w 'web:%{http_code}\n' http://localhost:8080/
curl -s -o /dev/null -w 'app.js:%{http_code}\n' http://localhost:8080/app.js
# expect {"jsonrpc":"2.0","result":{"version":"1.37.0",...}}
curl -s http://localhost:6800/jsonrpc -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"aria2.getVersion","params":["token:dev"]}'
podman exec aria2c-dev ps -o pid,args
podman logs aria2c-dev
podman rm -f aria2c-dev
```

Notes:

- The base image already ships UID/GID 1000 (`ubuntu` user), so the image creates `aria2` with UID/GID 1001.
- RPC-relevant settings (`enable-rpc`, `rpc-listen-all`, port, `dir`, session file) are baked into the config file so RPC is always on.
- `--rpc-secret` is mandatory; the entrypoint exits with an error if it is missing or empty.
- The entrypoint (PID 1) validates the `/downloads` mount, parses/validates options into the config file, starts `node-server.js` on port `8080`, and runs `aria2c`; on exit it terminates both children.
- `curl` used to fetch `webui-aria2` during build is purged afterwards; the image keeps only `aria2`, `ca-certificates`, and `nodejs` as extra packages.
- Image manifest is OCI (`application/vnd.oci.image.manifest.v1+json`); built and run with `crun`.

## Layout

```
aria2c/
├── Containerfile   # OCI image definition (fetches webui-aria2, installs node)
├── entrypoint.sh   # mount validation + parses options into aria2.conf + runs web UI and aria2c
└── README.md       # this file
```