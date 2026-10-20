#!/usr/bin/env bash
# 사용법: scripts/setup-aws-iam.sh            # 실제 적용
#         DRY_RUN=1 scripts/setup-aws-iam.sh  # 실행될 aws 명령만 출력
#
# GitHub Actions → ECR 푸시용 OIDC 공급자 + IAM 역할, ECS 실행/태스크 역할을 만든다.
# 여러 번 실행해도 안전하다 (있으면 정책만 최신 내용으로 덮어쓴다).
#
# 만드는 것
#   1) OIDC 공급자 token.actions.githubusercontent.com   (계정당 1개)
#   2) cdi-github-ecr-push       : GitHub(main 브랜치)만 맡을 수 있는 역할 + cdi/* ECR 푸시 권한
#   3) cdi-ecs-execution-role    : 이미지 pull · 로그 · cdi/* 시크릿 읽기 (ECS 에이전트가 사용)
#   4) cdi-postgres-task-role    : EFS 마운트 (EFS_ID, EFS_ACCESS_POINT_ID 가 있을 때만)
#
# 필요 권한: 실행하는 사람에게 IAM 관리 권한 (iam:CreateRole, iam:PutRolePolicy, iam:CreateOpenIDConnectProvider …)
set -euo pipefail
. "$(dirname "$0")/lib.sh"

command -v aws >/dev/null || die "aws CLI v2 가 필요합니다: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"

: "${AWS_REGION:?AWS_REGION 이 필요합니다 (.env)}"
GITHUB_REPO="${GITHUB_REPO:-yeomyaloo/create-docker-image}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
PUSH_ROLE="${PUSH_ROLE:-cdi-github-ecr-push}"
EXEC_ROLE="${EXEC_ROLE:-cdi-ecs-execution-role}"
TASK_ROLE="${TASK_ROLE:-cdi-postgres-task-role}"
OIDC_HOST="token.actions.githubusercontent.com"
DRY_RUN="${DRY_RUN:-}"

# 지금 로그인한 계정을 확인한다 → 엉뚱한 계정에 만드는 사고 방지
CALLER="$(aws sts get-caller-identity --query Arn --output text)" || die "AWS 로그인이 필요합니다 (aws configure / aws sso login)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [ -n "${AWS_ACCOUNT_ID:-}" ] && [ "$AWS_ACCOUNT_ID" != "$ACCOUNT_ID" ]; then
  die ".env 의 AWS_ACCOUNT_ID($AWS_ACCOUNT_ID)와 로그인한 계정($ACCOUNT_ID)이 다릅니다"
fi
log "계정: $ACCOUNT_ID / 리전: $AWS_REGION / 실행자: $CALLER"
log "GitHub: $GITHUB_REPO ($GITHUB_BRANCH 브랜치)${DRY_RUN:+  [DRY_RUN]}"

run() {
  if [ -n "$DRY_RUN" ]; then printf '  + %s\n' "$*" >&2; else "$@"; fi
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 템플릿의 <자리표시자>를 실제 값으로 바꾼 파일 경로를 출력
render() {
  local out="$TMP_DIR/$(basename "$1")"
  sed -e "s|<ACCOUNT_ID>|$ACCOUNT_ID|g" -e "s|<REGION>|$AWS_REGION|g" \
      -e "s|<GITHUB_REPO>|$GITHUB_REPO|g" -e "s|<GITHUB_BRANCH>|$GITHUB_BRANCH|g" \
      -e "s|<EFS_ID>|${EFS_ID:-}|g" -e "s|<EFS_ACCESS_POINT_ID>|${EFS_ACCESS_POINT_ID:-}|g" \
      "$1" > "$out"
  # aws CLI 의 file:// 는 Windows 에서 Windows 경로를 기대한다
  if command -v cygpath >/dev/null; then cygpath -m "$out"; else echo "$out"; fi
}

# 역할이 없으면 만들고, 있으면 신뢰 정책을 최신으로 갱신
ensure_role() {
  local name="$1" trust="$2" desc="$3"
  if aws iam get-role --role-name "$name" >/dev/null 2>&1; then
    log "역할 갱신: $name"
    run aws iam update-assume-role-policy --role-name "$name" --policy-document "file://$trust"
  else
    log "역할 생성: $name"
    run aws iam create-role --role-name "$name" --assume-role-policy-document "file://$trust" \
      --description "$desc" --max-session-duration 3600 \
      --tags Key=project,Value=create-docker-image >/dev/null
  fi
}

# ---------------------------------------------------------------- 1) OIDC 공급자
OIDC_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/${OIDC_HOST}"
if aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$OIDC_ARN" >/dev/null 2>&1; then
  log "OIDC 공급자 이미 있음: $OIDC_HOST"
else
  log "OIDC 공급자 생성: $OIDC_HOST"
  # thumbprint 는 생략: AWS 가 GitHub OIDC 는 신뢰된 CA 로 직접 검증한다 (aws CLI v2 최신 버전 필요)
  run aws iam create-open-id-connect-provider --url "https://${OIDC_HOST}" \
    --client-id-list sts.amazonaws.com \
    --tags Key=project,Value=create-docker-image >/dev/null
fi

# ---------------------------------------------------------------- 2) GitHub → ECR 푸시 역할
ensure_role "$PUSH_ROLE" "$(render aws/iam/github-oidc-trust-policy.json)" \
  "GitHub Actions ($GITHUB_REPO@$GITHUB_BRANCH) pushes images to ECR cdi/*"
run aws iam put-role-policy --role-name "$PUSH_ROLE" --policy-name ecr-push \
  --policy-document "file://$(render aws/iam/ecr-push-policy.json)"

# ---------------------------------------------------------------- 3) ECS 실행 역할
ensure_role "$EXEC_ROLE" "$(render aws/iam/ecs-tasks-trust-policy.json)" \
  "ECS agent: pull images from ECR, write logs, read cdi/* secrets"
run aws iam attach-role-policy --role-name "$EXEC_ROLE" \
  --policy-arn arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy
run aws iam put-role-policy --role-name "$EXEC_ROLE" --policy-name read-cdi-secrets \
  --policy-document "file://$(render aws/iam/ecs-execution-secrets-policy.json)"

# ---------------------------------------------------------------- 4) ECS 태스크 역할 (EFS 가 준비된 경우)
if [ -n "${EFS_ID:-}" ] && [ -n "${EFS_ACCESS_POINT_ID:-}" ]; then
  ensure_role "$TASK_ROLE" "$(render aws/iam/ecs-tasks-trust-policy.json)" \
    "cdi-postgres task: mount EFS access point"
  run aws iam put-role-policy --role-name "$TASK_ROLE" --policy-name efs-mount \
    --policy-document "file://$(render aws/iam/ecs-task-role-policy.json)"
else
  log "건너뜀: $TASK_ROLE (EFS_ID, EFS_ACCESS_POINT_ID 를 지정하면 함께 만든다 — docs/04-aws.md 2단계 이후)"
fi

# ---------------------------------------------------------------- 5) GitHub 저장소 Variables
PUSH_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${PUSH_ROLE}"
if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  log "GitHub Variables 설정: $GITHUB_REPO"
  run gh variable set AWS_ROLE_ARN   --repo "$GITHUB_REPO" --body "$PUSH_ROLE_ARN"
  run gh variable set AWS_REGION     --repo "$GITHUB_REPO" --body "$AWS_REGION"
  run gh variable set AWS_ACCOUNT_ID --repo "$GITHUB_REPO" --body "$ACCOUNT_ID"
else
  log "gh CLI 가 없어 GitHub Variables 는 직접 넣어 주세요:"
  log "  https://github.com/$GITHUB_REPO/settings/variables/actions"
  printf '    AWS_ROLE_ARN   = %s\n    AWS_REGION     = %s\n    AWS_ACCOUNT_ID = %s\n' \
    "$PUSH_ROLE_ARN" "$AWS_REGION" "$ACCOUNT_ID" >&2
fi

log "완료. 확인: aws iam get-role --role-name $PUSH_ROLE --query Role.AssumeRolePolicyDocument"
