#!/bin/bash
set -euo pipefail

LOCALGATE_PID=""

cleanup() {
    if [ -n "$LOCALGATE_PID" ] && kill -0 "$LOCALGATE_PID" 2>/dev/null; then
        kill "$LOCALGATE_PID"
        wait "$LOCALGATE_PID" 2>/dev/null || true
    fi
    LOCALGATE_PID=""
}

if [ -n "${LOCALGATE_SERVER:-}" ]; then
    if [ -n "${LOCALGATE_VERBOSE:-}" ]; then
        setsid localgate watch --server "$LOCALGATE_SERVER" &
    else
        setsid localgate watch --server "$LOCALGATE_SERVER" >/dev/null 2>&1 &
    fi
    LOCALGATE_PID=$!
fi

trap cleanup EXIT
trap 'cleanup; exit' TERM

"$@"
