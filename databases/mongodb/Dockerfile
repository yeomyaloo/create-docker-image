# syntax=docker/dockerfile:1
# ① 베이스 이미지: 공식 이미지 + 헬스체크
ARG VERSION=7.0
FROM mongo:${VERSION}

LABEL org.opencontainers.image.source="https://github.com/yeomyaloo/create-docker-image" \
      org.opencontainers.image.description="MongoDB base image (healthcheck)"

ENV TZ=Asia/Seoul

HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
  CMD mongosh --quiet --eval "quit(db.adminCommand('ping').ok ? 0 : 1)" || exit 1

EXPOSE 27017
