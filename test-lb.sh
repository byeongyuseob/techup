#!/bin/bash
echo "Testing load balancing across scaled containers..."
for i in {1..20}; do
    result=$(curl -s http://localhost:8088/hostname.php)
    echo "$result"
done | sort | uniq -c | sort -n