# aria2c

OCI-compliant [aria2](https://aria2.github.io/) download daemon image with JSON-RPC/XML-RPC enabled, built and run with [Podman](https://podman.io/). Base image: `ubuntu:noble`.

## Dependencies

- [Podman](https://podman.io/) 4.0+ (uses `crun` as the OCI runtime)
- Network access to pull `docker.io/library/ubuntu:noble` and install apt packages
- Port `6800` (RPC) free on the host when published

## Build

```sh
podman build -t localhost/aria2c:latest .
```

## Run

A host path must be mounted at `/downloads`; the container refuses to start otherwise.

```sh
mkdir -p "$PWD/downloads"
podman run -d \
  --name aria2c \
  -p 6800:6800 \
  -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest
```

Notes on the `/downloads` mount:

- It must be provided. Without it the container exits immediately:
  `ERROR: /downloads is not mounted.`
- It must be a host path bind mount (`-v /host/path:/downloads`). Named or anonymous container volumes are rejected:
  `ERROR: /downloads must be mounted from a host directory, not a container volume.`
- The container runs as UID 1001, so the host directory must be writable by that UID (e.g. `chown -R 1001:1001 downloads`).

`/home/aria2/.aria2` holds the generated config file `aria2.conf` and the session file `aria2.session` (saved every 60 seconds). Mount it at `-v "$PWD/aria2-config:/home/aria2/.aria2"` to persist config and session across container removal; leave it mounted as an anonymous volume otherwise. The entrypoint rewrites the config file on every start, so configuration is never stale.

## Usage

The RPC endpoint listens on all interfaces at `http://localhost:6800/jsonrpc`. Example JSON-RPC call:

```sh
curl -s http://localhost:6800/jsonrpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"aria2.getVersion","params":[]}'
```

Forward a URI into the download queue from the host:

```sh
curl -s http://localhost:6800/jsonrpc \
  -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"aria2.addUri","params":[["https://example.com/file.iso"]]}'
```

### Configuration options

Pass options to the `podman run` command after the image name. The entrypoint **parses them, validates them, and writes them to `/home/aria2/.aria2/aria2.conf`** in native aria2 config format, then starts `aria2c` with `--conf-path=/home/aria2/.aria2/aria2.conf`. Options are not forwarded to the command line.

| Option                        | Config line                 | Valid values                    |
| ----------------------------- | --------------------------- | ------------------------------- |
| `--continue[=true\|false]`     | `continue=true`             | `true`, `false` (bare = true)   |
| `--file-allocation=<m>`       | `file-allocation=none`      | `none`, `prealloc`, `falloc`    |
| `--max-concurrent-downloads=<n>` | `max-concurrent-downloads=3` | number                        |
| `--max-overall-download-limit=<s>` | `max-overall-download-limit=1M` | size (e.g. `0`, `100K`, `1M`) |
| `--max-connection-per-server=<n>` | `max-connection-per-server=4` | number                       |
| `--min-split-size=<s>`        | `min-split-size=1M`         | size (e.g. `1M`)                |
| `--split=<n>`                 | `split=5`                   | number                          |
| `--rpc-secret=<token>`        | `rpc-secret=changeme`       | non-empty token                 |

Example:

```sh
podman run -d \
  --name aria2c \
  -p 6800:6800 \
  -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest \
    --continue \
    --file-allocation=none \
    --max-concurrent-downloads=3 \
    --max-overall-download-limit=1M \
    --max-connection-per-server=4 \
    --min-split-size=1M \
    --split=5 \
    --rpc-secret=changeme
```

The resulting `aria2.conf`:

```ini
enable-rpc=true
rpc-listen-all=true
rpc-listen-port=6800
dir=/downloads
save-session=/home/aria2/.aria2/aria2.session
save-session-interval=60
continue=true
file-allocation=none
max-concurrent-downloads=3
max-overall-download-limit=1M
max-connection-per-server=4
min-split-size=1M
split=5
rpc-secret=changeme
```

`aria2c` refuses unknown `--` options with a usage error (`ERROR: unsupported option: --...`) and rejects invalid values (`ERROR: invalid value for --split: 'abc'`). Arguments that are not options are treated as download URIs and passed to `aria2c`:

```sh
podman run -d -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest https://example.com/file.iso
```

Defaults:

| Setting              | Value                                             |
| -------------------- | ------------------------------------------------- |
| RPC port             | 6800                                              |
| RPC listener         | all interfaces                                     |
| Download dir         | `/downloads` (host path mount, required)          |
| Config file          | `/home/aria2/.aria2/aria2.conf`                   |
| Session file         | `/home/aria2/.aria2/aria2.session` (saved 60s)    |
| User                 | `aria2` (UID 1001, GID 1001), non-root           |

## Development

Iterate on the image and verify the parsed configuration:

```sh
podman build -t localhost/aria2c:latest .
mkdir -p "$PWD/downloads"
podman run -d --name aria2c-dev \
  -p 6800:6800 \
  -v "$PWD/downloads:/downloads" \
  localhost/aria2c:latest --continue --split=4 --rpc-secret=dev
podman exec aria2c-dev cat /home/aria2/.aria2/aria2.conf
# expect {"jsonrpc":"2.0","result":{"version":"1.37.0",...}}
curl -s http://localhost:6800/jsonrpc -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":"1","method":"aria2.getVersion","params":["token:dev"]}'
podman logs aria2c-dev
podman rm -f aria2c-dev
```

Notes:

- The base image already ships UID/GID 1000 (`ubuntu` user), so the image creates `aria2` with UID/GID 1001.
- RPC-relevant settings (`enable-rpc`, `rpc-listen-all`, port, `dir`, session file) are baked into the config file so RPC is always on.
- The entrypoint validates the `/downloads` mount, parses/validates options into the config file, and forwards any remaining non-option arguments as download URIs.
- Image manifest is OCI (`application/vnd.oci.image.manifest.v1+json`); built and run with `crun`.

## Layout

```
aria2c/
├── Containerfile   # OCI image definition
├── entrypoint.sh   # mount validation + parses options into aria2.conf + launches aria2c
└── README.md       # this file
```