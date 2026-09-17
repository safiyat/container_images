#!/bin/sh
set -eu

CONF_DIR=/home/aria2/.aria2
CONF_PATH="$CONF_DIR/aria2.conf"

downloads_src="$(awk '$2 == "/downloads" { print $1; exit }' /proc/self/mounts 2>/dev/null || true)"

if [ -z "$downloads_src" ]; then
    echo "ERROR: /downloads is not mounted." >&2
    echo "This image requires a host path mount for the download directory:" >&2
    echo "  podman run -v /absolute/host/path:/downloads ..." >&2
    exit 1
fi

case "$downloads_src" in
    /dev/*|*containers/storage/volumes/*|*docker/volumes/*)
        echo "ERROR: /downloads must be mounted from a host directory, not a container volume." >&2
        echo "  podman run -v /absolute/host/path:/downloads ..." >&2
        exit 1
        ;;
esac

mkdir -p "$CONF_DIR"

{
    echo "enable-rpc=true"
    echo "rpc-listen-all=true"
    echo "rpc-listen-port=6800"
    echo "dir=/downloads"
    echo "save-session=$CONF_DIR/aria2.session"
    echo "save-session-interval=60"
} > "$CONF_PATH"

is_int() {
    case "$1" in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

is_size() {
    case "$1" in
        ''|*[!0-9KkMmGg]*) return 1 ;;
    esac
    return 0
}

set_option() {
    echo "$1=$2" >> "$CONF_PATH"
}

uris=
err=

for arg in "$@"; do
    value="${arg#*=}"
    case "$arg" in
        --continue)
            set_option continue true
            ;;
        --continue=*)
            case "$value" in
                true|false)
                    set_option continue "$value"
                    ;;
                *)
                    err="invalid value for --continue: '$value' (expected true or false)"
                    break
                    ;;
            esac
            ;;
        --file-allocation=*)
            case "$value" in
                none|prealloc|falloc)
                    set_option file-allocation "$value"
                    ;;
                *)
                    err="invalid value for --file-allocation: '$value' (expected none, prealloc, or falloc)"
                    break
                    ;;
            esac
            ;;
        --max-concurrent-downloads=*)
            if is_int "$value"; then
                set_option max-concurrent-downloads "$value"
            else
                err="invalid value for --max-concurrent-downloads: '$value' (expected a number)"
                break
            fi
            ;;
        --max-overall-download-limit=*)
            if is_size "$value"; then
                set_option max-overall-download-limit "$value"
            else
                err="invalid value for --max-overall-download-limit: '$value' (expected e.g. 0, 100K, 1M)"
                break
            fi
            ;;
        --max-connection-per-server=*)
            if is_int "$value"; then
                set_option max-connection-per-server "$value"
            else
                err="invalid value for --max-connection-per-server: '$value' (expected a number)"
                break
            fi
            ;;
        --min-split-size=*)
            if is_size "$value"; then
                set_option min-split-size "$value"
            else
                err="invalid value for --min-split-size: '$value' (expected e.g. 1M)"
                break
            fi
            ;;
        --split=*)
            if is_int "$value"; then
                set_option split "$value"
            else
                err="invalid value for --split: '$value' (expected a number)"
                break
            fi
            ;;
        --rpc-secret=*)
            if [ -z "$value" ]; then
                err="invalid value for --rpc-secret: value must not be empty"
                break
            fi
            set_option rpc-secret "$value"
            ;;
        --*)
            err="unsupported option: $arg"
            break
            ;;
        *)
            uris="$uris $arg"
            ;;
    esac
done

if [ -n "$err" ]; then
    echo "ERROR: $err" >&2
    echo "Supported options, written to $CONF_PATH:" >&2
    echo "  --continue[=true|false]" >&2
    echo "  --file-allocation=none|prealloc|falloc" >&2
    echo "  --max-concurrent-downloads=<number>" >&2
    echo "  --max-overall-download-limit=<speed>" >&2
    echo "  --max-connection-per-server=<number>" >&2
    echo "  --min-split-size=<size>" >&2
    echo "  --split=<number>" >&2
    echo "  --rpc-secret=<token>" >&2
    exit 1
fi

# shellcheck disable=SC2086
exec /usr/bin/aria2c --conf-path="$CONF_PATH" $uris