#!/usr/bin/env bash
# 사용법: scripts/run.sh <db> [base|schema|baked]
#   .env 의 DB_USER/DB_NAME/DB_PASSWORD 를 DB별 환경변수 이름으로 바꿔 컨테이너를 띄운다.
#   HOST_PORT=15432 처럼 지정하면 호스트 포트를 바꿀 수 있다.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DB="${1:?사용법: $0 <db> [base|schema|baked]}"
VARIANT="${2:-base}"
require_variant "$DB" "$VARIANT"
: "${DB_PASSWORD:?.env 에 DB_PASSWORD 를 설정하세요 (cp .env.example .env)}"

IMAGE="$(image_ref "$DB" "$VARIANT")"
NAME="$(container_name "$DB" "$VARIANT")"
PORT="$(db_port "$DB")"
HOST_PORT="${HOST_PORT:-$PORT}"

docker image inspect "$IMAGE" >/dev/null 2>&1 || die "이미지가 없습니다: $IMAGE → scripts/build.sh $DB $VARIANT"

# 같은 개념(계정/DB/비밀번호)이 DB마다 환경변수 이름만 다르다 → 여기서 한 번에 매핑
case "$DB" in
  postgres)
    ENV_ARGS=(-e "POSTGRES_USER=$DB_USER" -e "POSTGRES_DB=$DB_NAME" -e "POSTGRES_PASSWORD=$DB_PASSWORD") ;;
  mysql)
    ENV_ARGS=(-e "MYSQL_ROOT_PASSWORD=$DB_PASSWORD" -e "MYSQL_DATABASE=$DB_NAME"
              -e "MYSQL_USER=$DB_USER" -e "MYSQL_PASSWORD=$DB_PASSWORD") ;;
  mariadb)
    ENV_ARGS=(-e "MARIADB_ROOT_PASSWORD=$DB_PASSWORD" -e "MARIADB_DATABASE=$DB_NAME"
              -e "MARIADB_USER=$DB_USER" -e "MARIADB_PASSWORD=$DB_PASSWORD") ;;
  mongodb)
    ENV_ARGS=(-e "MONGO_INITDB_ROOT_USERNAME=$DB_USER" -e "MONGO_INITDB_ROOT_PASSWORD=$DB_PASSWORD"
              -e "MONGO_INITDB_DATABASE=$DB_NAME") ;;
  redis)
    ENV_ARGS=(-e "REDIS_PASSWORD=$DB_PASSWORD") ;;
esac

# baked 는 데이터가 이미지 안에 있으므로 볼륨을 붙이지 않는다
VOL_ARGS=()
if [ "$VARIANT" != baked ]; then
  VOL_ARGS=(-v "${NAME}-data:$(db_data_dir "$DB")")
fi

docker rm -f "$NAME" >/dev/null 2>&1 || true
log "실행: $NAME ($IMAGE) → localhost:$HOST_PORT"
docker run -d --name "$NAME" -p "$HOST_PORT:$PORT" "${ENV_ARGS[@]}" "${VOL_ARGS[@]}" "$IMAGE" >/dev/null
log "검증: scripts/test.sh $DB $VARIANT   /   로그: docker logs -f $NAME"
