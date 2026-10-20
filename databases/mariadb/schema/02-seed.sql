INSERT IGNORE INTO users (email, name) VALUES
    ('alice@example.com', 'Alice'),
    ('bob@example.com',   'Bob');

INSERT INTO orders (user_id, amount, status)
SELECT id, 15000, 'PAID' FROM users WHERE email = 'alice@example.com';
