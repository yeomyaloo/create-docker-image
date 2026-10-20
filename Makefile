# 스크립트를 짧게 부르기 위한 래퍼. 실제 로직은 scripts/*.sh 에 있다 (make 가 없으면 스크립트를 직접 실행).
#   make build DB=mysql
#   make schema DB=postgres && make run DB=postgres VARIANT=schema && make test DB=postgres VARIANT=schema
DB      ?= postgres
VARIANT ?= base
DBS     := postgres mysql mariadb mongodb redis

.PHONY: build schema baked run test stop purge push build-all

build:  ; bash scripts/build.sh $(DB) $(VARIANT)
schema: ; bash scripts/build.sh $(DB) schema
baked:  ; bash scripts/build.sh $(DB) baked
run:    ; bash scripts/run.sh $(DB) $(VARIANT)
test:   ; bash scripts/test.sh $(DB) $(VARIANT)
stop:   ; bash scripts/stop.sh $(DB) $(VARIANT)
purge:  ; bash scripts/stop.sh $(DB) $(VARIANT) --purge
push:   ; bash scripts/push-ecr.sh $(DB)

build-all:
	@for db in $(DBS); do bash scripts/build.sh $$db base || exit 1; done
