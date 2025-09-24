USE testdb;

CREATE TABLE IF NOT EXISTS test_users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
    email VARCHAR(100) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

INSERT INTO test_users (name, email) VALUES
('John Smith', 'john.smith@example.com'),
('Alice Johnson', 'alice.johnson@example.com'),
('Bob Wilson', 'bob.wilson@example.com'),
('Sarah Davis', 'sarah.davis@example.com'),
('Michael Brown', 'michael.brown@example.com');