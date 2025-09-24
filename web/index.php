<?php header('Content-Type: text/html; charset=UTF-8'); ?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Load Balancer Test</title>
</head>
<body>
    <h1>Load Balancer Test</h1>
    <p>Server: <?php echo gethostname(); ?></p>
    <p>Current Time: <?php echo date('Y-m-d H:i:s'); ?></p>

    <?php
    // MySQL 연결 테스트
    $host = 'mysql';
    $dbname = 'testdb';
    $username = 'root';
    $password = 'naver123';

    try {
        $pdo = new PDO("mysql:host=$host;dbname=$dbname", $username, $password);
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

        echo "<h2>MySQL Connection: SUCCESS</h2>";

        // 테스트 테이블에서 데이터 조회
        $stmt = $pdo->query("SELECT * FROM test_users ORDER BY id LIMIT 5");
        $users = $stmt->fetchAll(PDO::FETCH_ASSOC);

        echo "<h3>Test Users:</h3>";
        echo "<table border='1'>";
        echo "<tr><th>ID</th><th>Name</th><th>Email</th><th>Created</th></tr>";
        foreach ($users as $user) {
            echo "<tr>";
            echo "<td>" . htmlspecialchars($user['id']) . "</td>";
            echo "<td>" . htmlspecialchars($user['name']) . "</td>";
            echo "<td>" . htmlspecialchars($user['email']) . "</td>";
            echo "<td>" . htmlspecialchars($user['created_at']) . "</td>";
            echo "</tr>";
        }
        echo "</table>";

    } catch (PDOException $e) {
        echo "<h2>MySQL Connection: FAILED</h2>";
        echo "<p>Error: " . $e->getMessage() . "</p>";
    }
    ?>

    <hr>
    <p><a href='/nfs/'>NFS Shared Folder</a></p>
</body>
</html>