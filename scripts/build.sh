#!/usr/bin/env bash
# 사용법: scripts/build.sh <db> [base|schema|baked]
#   예) scripts/build.sh postgres          → cdi/postgres:16
#       scripts/build.sh postgres schema   → cdi/postgres:16-schema (베이스가 없으면 먼저 빌드)
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DB="${1:?사용법: $0 <db> [base|schema|baked]}"
VARIANT="${2:-base}"
require_variant "$DB" "$VARIANT"

BASE_IMAGE="$(image_ref "$DB" base)"
TARGET="$(image_ref "$DB" "$VARIANT")"

# schema/baked 는 우리 베이스 이미지를 FROM 으로 쓴다 → 계층 구조: 공식 → base → schema
if [ "$VARIANT" != base ] && ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  log "베이스 이미지가 없어 먼저 빌드합니다: $BASE_IMAGE"
  bash scripts/build.sh "$DB" base
fi

set_build_args "$DB" "$VARIANT" "$BASE_IMAGE"
log "빌드: $TARGET"
DOCKER_BUILDKIT=1 docker build "${BUILD_ARGS[@]}" -t "$TARGET" "databases/$DB"
size_mb="$(docker image inspect -f '{{.Size}}' "$TARGET" | awk '{printf "%.0f", $1/1024/1024}')"
log "완료: $TARGET (${size_mb}MB)"
