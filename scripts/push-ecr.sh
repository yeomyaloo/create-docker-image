#!/usr/bin/env bash
# 사용법: scripts/push-ecr.sh <db> [variant ...]
#   변형을 생략하면 base + (있으면) schema 를 올린다. baked 는 명시해야 올라간다.
#   예) scripts/push-ecr.sh postgres
#       scripts/push-ecr.sh postgres base schema baked
#
# 왜 buildx --push 인가?
#   - Fargate Graviton(arm64)과 x86 둘 다에서 돌도록 멀티 아키텍처 매니페스트로 올린다.
#   - 멀티 아키 이미지는 로컬 이미지 저장소에 load 할 수 없어서, 빌드와 동시에 레지스트리로 push 한다.
#   - 그래서 schema 변형의 BASE_IMAGE 도 로컬 태그가 아니라 "ECR에 방금 올린 base"를 가리킨다.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

DB="${1:?사용법: $0 <db> [variant ...]}"
shift
db_version "$DB" >/dev/null
if [ $# -gt 0 ]; then
  VARIANTS=("$@")
else
  VARIANTS=(base)
  if [ -f "databases/$DB/Dockerfile.schema" ]; then VARIANTS+=(schema); fi
fi

: "${AWS_REGION:?AWS_REGION 이 필요합니다}"
: "${AWS_ACCOUNT_ID:?AWS_ACCOUNT_ID 가 필요합니다}"
command -v aws >/dev/null || die "aws CLI 가 필요합니다"

REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO="${ECR_PREFIX:-cdi}/${DB}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo local)"
BUILDER="cdi-builder"

# 1) 저장소가 없으면 생성: 푸시 시 취약점 스캔 + 수명주기 정책(오래된 이미지 자동 정리)
if ! aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$REPO" >/dev/null 2>&1; then
  log "ECR 저장소 생성: $REPO"
  aws ecr create-repository --region "$AWS_REGION" --repository-name "$REPO" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 >/dev/null
  aws ecr put-lifecycle-policy --region "$AWS_REGION" --repository-name "$REPO" \
    --lifecycle-policy-text file://aws/ecr-lifecycle-policy.json >/dev/null
fi

# 2) 로그인: 12시간짜리 임시 토큰 (장기 비밀번호를 어디에도 저장하지 않는다)
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$REGISTRY"

# 3) 멀티 아키 빌더 (docker-container 드라이버여야 여러 플랫폼을 한 번에 빌드할 수 있다)
if ! docker buildx inspect "$BUILDER" >/dev/null 2>&1; then
  docker buildx create --name "$BUILDER" --driver docker-container >/dev/null
fi

# base 를 항상 먼저 올린다 (schema/baked 가 그것을 FROM 으로 쓰므로)
ordered=(base)
for v in "${VARIANTS[@]}"; do
  if [ "$v" != base ]; then ordered+=("$v"); fi
done

BASE_REF="${REGISTRY}/${REPO}:$(image_tag "$DB" base)"
for v in "${ordered[@]}"; do
  require_variant "$DB" "$v"
  tag="$(image_tag "$DB" "$v")"
  set_build_args "$DB" "$v" "$BASE_REF"
  log "push: ${REPO}:${tag} (${PLATFORMS})"
  # 같은 태그(16)는 덮어써지므로, 추적용으로 커밋 SHA 태그(16-abc1234)도 함께 남긴다
  docker buildx build --builder "$BUILDER" --platform "$PLATFORMS" --push \
    "${BUILD_ARGS[@]}" \
    -t "${REGISTRY}/${REPO}:${tag}" \
    -t "${REGISTRY}/${REPO}:${tag}-${GIT_SHA}" \
    "databases/$DB"
done
log "완료: https://${AWS_REGION}.console.aws.amazon.com/ecr/repositories/private/${AWS_ACCOUNT_ID}/${REPO}"
