# syntax=docker/dockerfile:1
# ① 베이스 이미지: 공식 이미지 + 설정 + 헬스체크
ARG VERSION=8.4
FROM mysql:${VERSION}

LABEL org.opencontainers.image.source="https://github.com/yeomyaloo/create-docker-image" \
      org.opencontainers.image.description="MySQL base image (config + healthcheck)"

# MySQL 은 world-writable 설정 파일을 무시한다 → 644 로 고정
COPY --chmod=644 conf/my.cnf /etc/mysql/conf.d/zz-cdi.cnf

# -h 127.0.0.1: 초기화 중 임시 서버는 --skip-networking 이라 TCP 응답이 없다.
# mysqladmin ping 은 인증 실패여도 서버가 살아 있으면 0 을 반환하므로 비밀번호가 필요 없다.
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=5 \
  CMD mysqladmin ping -h 127.0.0.1 --silent || exit 1

EXPOSE 3306
