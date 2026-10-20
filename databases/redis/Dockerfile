# syntax=docker/dockerfile:1
# ① 베이스 이미지: 공식 이미지 + 설정 + 비밀번호 강제 + 헬스체크
#    Redis 는 테이블 스키마 개념이 없어서 schema/baked 변형을 두지 않는다.
ARG VERSION=7.4
FROM redis:${VERSION}-alpine

LABEL org.opencontainers.image.source="https://github.com/yeomyaloo/create-docker-image" \
      org.opencontainers.image.description="Redis base image (config + required password + healthcheck)"

COPY --chmod=644 conf/redis.conf /usr/local/etc/redis/redis.conf
COPY --chmod=755 cdi-entrypoint.sh /usr/local/bin/cdi-entrypoint.sh

HEALTHCHECK --interval=10s --timeout=5s --start-period=10s --retries=5 \
  CMD redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping | grep -q PONG || exit 1

EXPOSE 6379
# 래퍼에서 비밀번호를 확인한 뒤 공식 엔트리포인트로 넘긴다 (redis 유저로 권한 강등은 공식 스크립트가 처리)
ENTRYPOINT ["cdi-entrypoint.sh"]
CMD []
