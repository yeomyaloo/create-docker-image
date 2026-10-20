# syntax=docker/dockerfile:1
# ① 베이스 이미지: 공식 이미지 + 설정 + 헬스체크. 스키마는 넣지 않는다.
#    공식 엔트리포인트(초기화·권한·시그널 처리)를 그대로 재사용하기 위해 공식 이미지 위에 얹는다.
ARG VERSION=16
FROM postgres:${VERSION}-alpine

LABEL org.opencontainers.image.source="https://github.com/yeomyaloo/create-docker-image" \
      org.opencontainers.image.description="PostgreSQL base image (config + healthcheck)"

COPY --chown=postgres:postgres --chmod=644 conf/postgresql.conf /etc/postgresql/postgresql.conf

# -h 127.0.0.1: 초기화 중 임시 서버는 유닉스 소켓만 열기 때문에,
#               TCP로 확인해야 "초기화가 끝난 진짜 서버"일 때만 healthy 가 된다.
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
  CMD pg_isready -h 127.0.0.1 -U "${POSTGRES_USER:-postgres}" || exit 1

EXPOSE 5432
CMD ["postgres", "-c", "config_file=/etc/postgresql/postgresql.conf"]
