#!/usr/bin/env bash
# 공통 설정: DB별 버전·포트·데이터 경로를 한 곳에서 관리한다.
# (버전이 여러 파일에 흩어지면 FROM 버전과 이미지 태그가 어긋나기 쉽다)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# Git Bash 가 `-e PGDATA=/var/...` 같은 인자를 Windows 경로로 바꿔버리는 것을 막는다.
# 대신 docker 에 넘기는 호스트 경로는 전부 저장소 루트 기준 상대경로로 쓴다.
export MSYS_NO_PATHCONV=1

if [ -f .env ]; then set -a; . ./.env; set +a; fi
IMAGE_PREFIX="${IMAGE_PREFIX:-cdi}"
DB_USER="${DB_USER:-app}"
DB_NAME="${DB_NAME:-app}"
SCHEMA_DIR="${SCHEMA_DIR:-schema}"

SUPPORTED_DBS="postgres mysql mariadb mongodb redis"

log() { printf '\033[36m[cdi]\033[0m %s\n' "$*" >&2; }
die() { printf '\033[31m[cdi] %s\033[0m\n' "$*" >&2; exit 1; }

db_version() {
  case "$1" in
    postgres) echo 16 ;;
    mysql)    echo 8.4 ;;
    mariadb)  echo 11.4 ;;
    mongodb)  echo 7.0 ;;
    redis)    echo 7.4 ;;
    *) die "지원하지 않는 DB: $1 (지원: $SUPPORTED_DBS)" ;;
  esac
}

db_port() {
  case "$1" in
    postgres) echo 5432 ;; mysql|mariadb) echo 3306 ;; mongodb) echo 27017 ;; redis) echo 6379 ;;
  esac
}

db_data_dir() {
  case "$1" in
    postgres) echo /var/lib/postgresql/data ;; mysql|mariadb) echo /var/lib/mysql ;;
    mongodb)  echo /data/db ;; redis) echo /data ;;
  esac
}

# base → Dockerfile, schema → Dockerfile.schema, baked → Dockerfile.baked
dockerfile_of() {
  if [ "$2" = base ]; then echo "databases/$1/Dockerfile"; else echo "databases/$1/Dockerfile.$2"; fi
}

require_variant() {
  db_version "$1" >/dev/null
  case "$2" in base|schema|baked) ;; *) die "variant 는 base|schema|baked 중 하나: $2" ;; esac
  [ -f "$(dockerfile_of "$1" "$2")" ] || die "$1 은(는) '$2' 변형을 지원하지 않습니다 ($(dockerfile_of "$1" "$2") 없음)"
}

# 이 DB가 지원하는 변형 목록 (Dockerfile 존재 여부로 판단)
variants_of() {
  local v out="base"
  for v in schema baked; do
    if [ -f "databases/$1/Dockerfile.$v" ]; then out="$out $v"; fi
  done
  echo "$out"
}

# 태그 규칙: 16 / 16-schema / 16-baked
image_tag() {
  if [ "$2" = base ]; then db_version "$1"; else echo "$(db_version "$1")-$2"; fi
}
image_ref() { echo "${IMAGE_PREFIX}/$1:$(image_tag "$1" "$2")"; }
container_name() { echo "cdi-$1-$2"; }

# 변형별 docker build 인자를 BUILD_ARGS 배열에 채운다. $3 = 베이스 이미지 참조
set_build_args() {
  local db="$1" variant="$2" base="$3"
  BUILD_ARGS=(-f "$(dockerfile_of "$db" "$variant")" --build-arg "VERSION=$(db_version "$db")")
  if [ "$variant" != base ]; then
    [ -d "databases/$db/$SCHEMA_DIR" ] || die "스키마 디렉터리가 없습니다: databases/$db/$SCHEMA_DIR"
    BUILD_ARGS+=(--build-arg "BASE_IMAGE=$base" --build-arg "SCHEMA_DIR=$SCHEMA_DIR")
  fi
  if [ "$variant" = baked ]; then
    : "${DB_PASSWORD:?baked 빌드에는 DB_PASSWORD 가 필요합니다 (.env)}"
    export DB_PASSWORD
    # BuildKit secret: 빌드 중 /run/secrets/db_password 로만 보이고 레이어에는 남지 않는다
    BUILD_ARGS+=(--secret "id=db_password,env=DB_PASSWORD"
                 --build-arg "DB_USER=$DB_USER" --build-arg "DB_NAME=$DB_NAME")
  fi
}
