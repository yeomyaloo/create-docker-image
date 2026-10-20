-- 엔트리포인트가 MYSQL_DATABASE 를 선택한 상태로 실행한다.
CREATE TABLE IF NOT EXISTS users (
    id          BIGINT       NOT NULL AUTO_INCREMENT PRIMARY KEY,
    email       VARCHAR(255) NOT NULL UNIQUE,
    name        VARCHAR(100) NOT NULL,
    created_at  DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS orders (
    id          BIGINT        NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id     BIGINT        NOT NULL,
    amount      DECIMAL(12,2) NOT NULL,
    status      ENUM('PENDING', 'PAID', 'CANCELLED') NOT NULL DEFAULT 'PENDING',
    created_at  DATETIME(3)   NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    CONSTRAINT fk_orders_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT chk_orders_amount CHECK (amount >= 0),
    INDEX idx_orders_user_id (user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
