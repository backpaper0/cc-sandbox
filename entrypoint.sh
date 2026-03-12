#!/bin/bash
set -euo pipefail

if [ -n "${LOCALGATE_SERVER:-}" ]; then
    if [ -n "${LOCALGATE_VERBOSE:-}" ]; then
        localgate watch --server "$LOCALGATE_SERVER" &
    else
        localgate watch --server "$LOCALGATE_SERVER" >/dev/null 2>&1 &
    fi
fi

exec "$@"
