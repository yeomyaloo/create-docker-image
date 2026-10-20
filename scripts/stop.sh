#!/usr/bin/env bash
# 사용법: scripts/stop.sh <db> [base|schema|baked] [--purge]
#   --purge 를 주면 데이터 볼륨까지 지운다 (schema 초기화를 다시 보고 싶을 때)
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DB="${1:?사용법: $0 <db> [base|schema|baked] [--purge]}"
VARIANT="${2:-base}"
NAME="$(container_name "$DB" "$VARIANT")"

if docker rm -f "$NAME" >/dev/null 2>&1; then log "삭제: $NAME"; else log "컨테이너 없음: $NAME"; fi
if [ "${3:-}" = --purge ]; then
  if docker volume rm "${NAME}-data" >/dev/null 2>&1; then log "볼륨 삭제: ${NAME}-data"; else log "볼륨 없음: ${NAME}-data"; fi
fi
