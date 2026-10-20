-- 시드 데이터 (필요 없으면 이 파일을 지운다)
INSERT INTO users (email, name) VALUES
    ('alice@example.com', 'Alice'),
    ('bob@example.com',   'Bob')
ON CONFLICT (email) DO NOTHING;

INSERT INTO orders (user_id, amount, status)
SELECT id, 15000, 'PAID' FROM users WHERE email = 'alice@example.com';
