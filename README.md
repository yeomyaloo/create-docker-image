# create-docker-image

PostgreSQL · MySQL · MariaDB · MongoDB · Redis를 **우리 설정이 들어간 Docker 이미지**로 만들고,
필요하면 **테이블 스키마까지 넣은 이미지**로 만든 뒤, **AWS ECR에 올려 ECS에서 실행**하는 스크립트와 문서 모음이다.

- 결과물: `cdi/postgres:16`, `cdi/postgres:16-schema` 같은 Docker 이미지 (`cdi` = **c**reate-**d**ocker-**i**mage, `.env`의 `IMAGE_PREFIX`로 변경 가능)
- 대상: 로컬 개발 · 테스트 · 스테이징용 DB. **운영 DB는 RDS/Aurora를 권장한다** ([이유](docs/04-aws.md))

![전체 흐름](docs/images/00-overview.svg)

## 용어: 이미지 3종류

같은 DB라도 목적에 따라 이미지를 세 단계로 나눈다. 뒤의 것은 앞의 것을 `FROM`으로 이어받는다.

| 종류 | 태그 예시 | 안에 든 것 | 컨테이너를 띄우면 | 언제 쓰나 |
|---|---|---|---|---|
| **base** | `cdi/postgres:16` | 공식 이미지 + 설정 파일 + 헬스체크 | 빈 DB가 만들어진다 | 스키마가 아직 없을 때 |
| **schema** | `cdi/postgres:16-schema` | base + 스키마 SQL 파일 | **처음 띄울 때** SQL이 실행돼 테이블이 생긴다 | 스키마가 정해진 뒤 개발 · 스테이징 |
| **baked** | `cdi/postgres:16-baked` | base + **테이블이 이미 만들어진 데이터** | 바로 사용 가능 (초기화 단계 없음) | 테스트 · CI (빠른 기동) |

> baked는 빌드할 때 쓴 비밀번호가 데이터에 남으므로 운영에 쓰지 않는다. 자세한 차이는 [③ 스키마 문서](docs/03-schema.md).

## 사전 준비

| 필요한 것 | 버전 / 비고 |
|---|---|
| Docker | Docker Desktop 또는 Engine **23 이상** (BuildKit 기본 활성 필요) |
| bash | Linux · macOS 기본 셸, Windows는 **Git Bash** |
| AWS CLI | **v2**, AWS에 올릴 때만 필요 |

```bash
git clone https://github.com/yeomyaloo/create-docker-image && cd create-docker-image
cp .env.example .env        # DB_PASSWORD 를 반드시 바꾼다 (.env 는 git 에 올라가지 않음)
```

## 사용법 — 하고 싶은 일별

### A. DB 하나를 그냥 띄우고 싶다 (base)

```bash
bash scripts/build.sh postgres          # 이미지 빌드 → cdi/postgres:16
bash scripts/run.sh   postgres          # 컨테이너 cdi-postgres-base 실행 → localhost:5432
bash scripts/test.sh  postgres          # 접속될 때까지 기다린 뒤 접속 확인 → "PASS"
docker exec -it cdi-postgres-base psql -U app -d app   # 직접 접속
```

`postgres` 자리에 `mysql`, `mariadb`, `mongodb`, `redis`를 넣으면 된다. 계정은 `.env`의 `DB_USER` / `DB_NAME` / `DB_PASSWORD`.

### B. 내 스키마를 넣은 이미지를 만들고 싶다 (schema)

1. `databases/<db>/schema/`의 예시 파일(`01-schema.sql`, `02-seed.sql`)을 **내 SQL로 바꾼다.**
   파일은 **이름 순서대로** 실행되므로 `01-`, `02-` 번호를 붙인다. MongoDB는 `.js` 파일이다.
2. 빌드 · 실행 · 확인:

```bash
bash scripts/build.sh postgres schema   # → cdi/postgres:16-schema
bash scripts/run.sh   postgres schema
bash scripts/test.sh  postgres schema   # 예시 스키마 기준으로 users · orders 테이블이 있는지 확인
```

> **주의:** 스키마 SQL은 **데이터가 비어 있을 때 한 번만** 실행된다. SQL을 고친 뒤 다시 적용하려면
> `bash scripts/stop.sh postgres schema --purge`로 데이터 볼륨까지 지우고 다시 실행한다.
> (`test.sh`는 예시 테이블 `users`, `orders`를 찾으므로 내 스키마로 바꿨다면 `test.sh` 결과 대신 직접 접속해 확인한다.)

### C. 테스트용으로 테이블이 미리 만들어진 이미지가 필요하다 (baked, postgres · mysql만)

```bash
bash scripts/build.sh postgres baked    # .env 의 DB_PASSWORD 로 계정이 만들어진 상태로 굳는다
bash scripts/run.sh   postgres baked    # 데이터 볼륨 없이 실행 → 컨테이너를 지우면 처음 상태로 돌아감
```

### D. AWS에 올리고 싶다

```bash
# 처음 한 번: GitHub Actions 가 AWS 키 없이 ECR 에 푸시할 수 있게 IAM 설정
aws sso login                             # IAM 관리 권한이 있는 계정
bash scripts/setup-aws-iam.sh             # DRY_RUN=1 을 앞에 붙이면 실행할 명령만 보여 준다

# 그 다음부터: 로컬에서 직접 올리거나, main 에 push 하면 GitHub Actions 가 올린다
bash scripts/push-ecr.sh postgres         # base + schema 를 x86 · ARM 겸용으로 ECR 에 푸시
```

`.env`에 `AWS_REGION`, `AWS_ACCOUNT_ID`가 있어야 한다. ECS 실행까지는 [④ AWS 문서](docs/04-aws.md).

### 정리

```bash
bash scripts/stop.sh postgres                 # 컨테이너만 삭제 (데이터는 볼륨에 남음)
bash scripts/stop.sh postgres base --purge    # 데이터 볼륨까지 삭제
```

## 지원 범위

| DB | 버전 | base | schema | baked | 호스트 포트 |
|---|---|:-:|:-:|:-:|---|
| PostgreSQL | 16 (alpine) | ✅ | ✅ | ✅ | 5432 |
| MySQL | 8.4 LTS | ✅ | ✅ | ✅ | 3306 |
| MariaDB | 11.4 LTS | ✅ | ✅ | ❌ ¹ | 3306 ² |
| MongoDB | 7.0 | ✅ | ✅ ³ | ❌ ¹ | 27017 |
| Redis | 7.4 (alpine) | ✅ | ❌ ⁴ | ❌ ⁴ | 6379 |

1. 아직 만들지 않았다. 방식은 postgres · mysql의 `Dockerfile.baked`와 같다.
2. MySQL과 같은 포트라서 둘을 동시에 띄우려면 한쪽에 `HOST_PORT=3307 bash scripts/run.sh mariadb`.
3. MongoDB에는 테이블이 없으므로 대신 컬렉션 + 필드 검증 규칙(`$jsonSchema`) + 인덱스를 만든다.
4. Redis는 키-값 저장소라 스키마 개념이 없다.

## 문서

| 단계 | 문서 | 이런 내용 |
|---|---|---|
| ① | [이미지 만들기](docs/01-build.md) | DB별로 무엇을 바꿨는지, 왜 공식 이미지 위에 얹었는지, 버전 올리는 법 |
| ② | [사용법](docs/02-usage.md) | `.env` 값이 DB별 환경변수로 바뀌는 표, 접속 문자열, docker compose 예시, 자주 겪는 문제 |
| ③ | [스키마 포함 이미지](docs/03-schema.md) | schema와 baked가 내부적으로 어떻게 다른지, 운영에서 스키마가 바뀔 때(마이그레이션) |
| ④ | [AWS](docs/04-aws.md) | IAM · OIDC 설정, ECR 푸시, ECS Fargate + EFS + Secrets Manager 실행, EC2 대안 |

## 폴더 구조

```
databases/<db>/
├── Dockerfile            # base
├── Dockerfile.schema     # schema
├── Dockerfile.baked      # baked (postgres, mysql)
├── conf/                 # DB 설정 파일 (문자셋, 타임존, 슬로우쿼리 로그 등)
└── schema/               # ← 내 스키마를 넣는 곳
scripts/
├── lib.sh                # DB별 버전 · 포트 · 태그 규칙 (버전은 여기서만 바꾼다)
├── build.sh  run.sh  test.sh  stop.sh
├── push-ecr.sh           # ECR 푸시
└── setup-aws-iam.sh      # AWS IAM · OIDC 1회 설정
aws/                      # IAM 정책 · ECS 태스크 정의 · ECR 수명주기 정책 (JSON)
.github/workflows/        # main 에 push 하면 ECR 로 자동 푸시
```

## 검증 상태

- 확인함: 스크립트 문법, JSON 형식, 다이어그램 렌더링, `setup-aws-iam.sh`의 실행 순서와 정책 값 (가짜 aws 명령으로 시험)
- **아직 확인 안 함:** 실제 이미지 빌드 · 실행 (작성 환경에 Docker가 없었음), 실제 AWS 계정 적용.
  처음 쓸 때는 A → B 순서로 `test.sh`가 PASS 하는지 먼저 확인할 것. 특히 baked는 공식 엔트리포인트 내부 구현에 기대므로 가장 깨지기 쉽다.
