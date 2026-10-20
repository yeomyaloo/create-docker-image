-- 엔트리포인트가 POSTGRES_DB 에 접속한 상태로 파일명 순서대로 실행한다.
CREATE TABLE IF NOT EXISTS users (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    email       VARCHAR(255) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS orders (
    id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id     BIGINT        NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    amount      NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    status      VARCHAR(20)   NOT NULL DEFAULT 'PENDING'
                CHECK (status IN ('PENDING', 'PAID', 'CANCELLED')),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders (user_id, created_at DESC);
