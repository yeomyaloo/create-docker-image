#!/bin/sh
# 비밀번호 없는 Redis 가 외부에 노출되는 사고를 막기 위해 REDIS_PASSWORD 를 필수로 한다.
set -e
: "${REDIS_PASSWORD:?REDIS_PASSWORD 환경변수가 필요합니다}"
exec docker-entrypoint.sh redis-server /usr/local/etc/redis/redis.conf --requirepass "$REDIS_PASSWORD" "$@"
