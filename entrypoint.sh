#!/bin/bash
set -euo pipefail

if [ -n "${LOCALGATE_SERVER:-}" ]; then
    localgate watch --server "$LOCALGATE_SERVER" &
fi

exec "$@"
