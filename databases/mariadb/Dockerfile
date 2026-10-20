# syntax=docker/dockerfile:1
# ① 베이스 이미지: 공식 이미지 + 설정 + 헬스체크
ARG VERSION=11.4
FROM mariadb:${VERSION}

LABEL org.opencontainers.image.source="https://github.com/yeomyaloo/create-docker-image" \
      org.opencontainers.image.description="MariaDB base image (config + healthcheck)"

COPY --chmod=644 conf/my.cnf /etc/mysql/conf.d/zz-cdi.cnf

# 공식 이미지 내장 healthcheck.sh: --connect 는 TCP 접속(=초기화 완료된 서버)까지 확인한다.
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
  CMD healthcheck.sh --connect --innodb_initialized || exit 1

EXPOSE 3306
