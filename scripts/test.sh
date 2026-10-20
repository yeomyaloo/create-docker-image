#!/usr/bin/env bash
# 사용법: scripts/test.sh <db> [base|schema|baked]
#   1) 헬스체크가 healthy 가 될 때까지 대기  2) 컨테이너 안 클라이언트로 접속
#   3) schema/baked 면 users·orders 가 실제로 만들어졌는지 확인
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DB="${1:?사용법: $0 <db> [base|schema|baked]}"
VARIANT="${2:-base}"
require_variant "$DB" "$VARIANT"
NAME="$(container_name "$DB" "$VARIANT")"
TIMEOUT="${TIMEOUT:-120}"

log "healthy 대기: $NAME (최대 ${TIMEOUT}s)"
status=starting
for ((i = 0; i < TIMEOUT; i += 2)); do
  status="$(docker inspect -f '{{.State.Health.Status}}' "$NAME" 2>/dev/null || echo missing)"
  [ "$status" = healthy ] && break
  [ "$status" = missing ] && die "컨테이너가 없습니다: $NAME → scripts/run.sh $DB $VARIANT"
  if [ "$(docker inspect -f '{{.State.Running}}' "$NAME")" != true ]; then
    docker logs --tail 50 "$NAME" >&2
    die "컨테이너가 종료되었습니다"
  fi
  sleep 2
done
if [ "$status" != healthy ]; then
  docker logs --tail 50 "$NAME" >&2
  die "시간 초과 (status=$status)"
fi

# 테이블/컬렉션 목록을 콤마로 구분해 출력
list_objects() {
  local tables_sql="SELECT GROUP_CONCAT(table_name ORDER BY table_name) FROM information_schema.tables WHERE table_schema = '$DB_NAME'"
  case "$DB" in
    postgres)
      docker exec -e "PGPASSWORD=$DB_PASSWORD" "$NAME" \
        psql -h 127.0.0.1 -U "$DB_USER" -d "$DB_NAME" -tAc \
        "SELECT string_agg(table_name, ',' ORDER BY table_name) FROM information_schema.tables WHERE table_schema = 'public'" ;;
    mysql)
      docker exec -e "MYSQL_PWD=$DB_PASSWORD" "$NAME" mysql -h 127.0.0.1 -u"$DB_USER" -N -e "$tables_sql" ;;
    mariadb)
      docker exec -e "MYSQL_PWD=$DB_PASSWORD" "$NAME" mariadb -h 127.0.0.1 -u"$DB_USER" -N -e "$tables_sql" ;;
    mongodb)
      docker exec "$NAME" mongosh --quiet -u "$DB_USER" -p "$DB_PASSWORD" --authenticationDatabase admin "$DB_NAME" \
        --eval "db.getCollectionNames().sort().join(',')" ;;
    redis)
      docker exec "$NAME" redis-cli --no-auth-warning -a "$DB_PASSWORD" ping ;;
  esac
}

if [ "$VARIANT" = base ]; then
  out="$(list_objects)" || die "접속 실패"
  log "PASS: 접속 성공 (${out:-객체 없음})"
  exit 0
fi

# MongoDB 는 초기화 중에도 localhost 핑이 성공할 수 있어 몇 번 재시도한다
out=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  out="$(list_objects 2>/dev/null || true)"
  if [[ ",$out," == *",orders,"* && ",$out," == *",users,"* ]]; then
    log "PASS: 스키마 확인 → $out"
    exit 0
  fi
  sleep 2
done
die "FAIL: users/orders 를 찾지 못했습니다 (조회 결과: ${out:-없음})"
