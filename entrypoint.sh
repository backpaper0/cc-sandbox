#!/bin/bash
set -euo pipefail

LOCALGATE_PID=""
DOCKERD_PID=""

cleanup() {
    if [ -n "$LOCALGATE_PID" ] && kill -0 "$LOCALGATE_PID" 2>/dev/null; then
        kill "$LOCALGATE_PID"
        wait "$LOCALGATE_PID" 2>/dev/null || true
    fi
    LOCALGATE_PID=""

    if [ -n "$DOCKERD_PID" ] && kill -0 "$DOCKERD_PID" 2>/dev/null; then
        kill "$DOCKERD_PID"
        wait "$DOCKERD_PID" 2>/dev/null || true
    fi
    DOCKERD_PID=""
}

trap cleanup EXIT
trap 'cleanup; exit' TERM

# Docker-in-Docker用のdockerdをバックグラウンドで起動する（root権限が必要）
dockerd >/var/log/dockerd.log 2>&1 &
DOCKERD_PID=$!

dockerd_ready=false
for _ in $(seq 1 30); do
    if docker info >/dev/null 2>&1; then
        dockerd_ready=true
        break
    fi
    sleep 1
done
if [ "$dockerd_ready" != "true" ]; then
    echo "警告: dockerdの起動を確認できませんでした（/var/log/dockerd.log を参照）。コンテナ内でのDocker利用はできない可能性があります。" >&2
fi

if [ -n "${LOCALGATE_SERVER:-}" ]; then
    if [ -n "${LOCALGATE_VERBOSE:-}" ]; then
        gosu "$CC_SANDBOX_USER" setsid localgate watch --server "$LOCALGATE_SERVER" &
    else
        gosu "$CC_SANDBOX_USER" setsid localgate watch --server "$LOCALGATE_SERVER" >/dev/null 2>&1 &
    fi
    LOCALGATE_PID=$!
fi

gosu "$CC_SANDBOX_USER" "$@"
