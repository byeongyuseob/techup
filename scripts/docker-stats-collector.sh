#!/bin/bash

# Docker Stats Collector Script
# Collects container resource usage and formats for Prometheus

STATS_FILE="/tmp/docker_stats.prom"
STATS_PORT=9999

# Function to collect docker stats
collect_stats() {
    echo "# HELP docker_container_cpu_percent Container CPU usage percentage" > ${STATS_FILE}
    echo "# TYPE docker_container_cpu_percent gauge" >> ${STATS_FILE}
    echo "# HELP docker_container_memory_usage_bytes Container memory usage in bytes" >> ${STATS_FILE}
    echo "# TYPE docker_container_memory_usage_bytes gauge" >> ${STATS_FILE}
    echo "# HELP docker_container_memory_limit_bytes Container memory limit in bytes" >> ${STATS_FILE}
    echo "# TYPE docker_container_memory_limit_bytes gauge" >> ${STATS_FILE}
    echo "# HELP docker_container_memory_percent Container memory usage percentage" >> ${STATS_FILE}
    echo "# TYPE docker_container_memory_percent gauge" >> ${STATS_FILE}
    echo "# HELP docker_container_network_rx_bytes Container network receive bytes" >> ${STATS_FILE}
    echo "# TYPE docker_container_network_rx_bytes gauge" >> ${STATS_FILE}
    echo "# HELP docker_container_network_tx_bytes Container network transmit bytes" >> ${STATS_FILE}
    echo "# TYPE docker_container_network_tx_bytes gauge" >> ${STATS_FILE}
    echo "# HELP docker_container_pids Container process count" >> ${STATS_FILE}
    echo "# TYPE docker_container_pids gauge" >> ${STATS_FILE}

    # Get docker stats in parseable format
    docker stats --no-stream --format "table {{.Container}}\t{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.PIDs}}" | tail -n +2 | while read line; do
        if [ ! -z "$line" ]; then
            # Parse the line
            container_id=$(echo $line | awk '{print $1}')
            name=$(echo $line | awk '{print $2}')
            cpu_percent=$(echo $line | awk '{print $3}' | sed 's/%//')
            mem_usage=$(echo $line | awk '{print $4}' | sed 's/MiB//')
            mem_limit=$(echo $line | awk '{print $6}' | sed 's/GiB//')
            mem_percent=$(echo $line | awk '{print $7}' | sed 's/%//')
            net_rx=$(echo $line | awk '{print $8}' | sed 's/MB//')
            net_tx=$(echo $line | awk '{print $10}' | sed 's/MB//')
            pids=$(echo $line | awk '{print $11}')

            # Convert units
            mem_usage_bytes=$(echo "$mem_usage * 1048576" | bc 2>/dev/null || echo "0")
            mem_limit_bytes=$(echo "$mem_limit * 1073741824" | bc 2>/dev/null || echo "0")
            net_rx_bytes=$(echo "$net_rx * 1000000" | bc 2>/dev/null || echo "0")
            net_tx_bytes=$(echo "$net_tx * 1000000" | bc 2>/dev/null || echo "0")

            # Output metrics
            echo "docker_container_cpu_percent{container_id=\"$container_id\",name=\"$name\"} $cpu_percent" >> ${STATS_FILE}
            echo "docker_container_memory_usage_bytes{container_id=\"$container_id\",name=\"$name\"} $mem_usage_bytes" >> ${STATS_FILE}
            echo "docker_container_memory_limit_bytes{container_id=\"$container_id\",name=\"$name\"} $mem_limit_bytes" >> ${STATS_FILE}
            echo "docker_container_memory_percent{container_id=\"$container_id\",name=\"$name\"} $mem_percent" >> ${STATS_FILE}
            echo "docker_container_network_rx_bytes{container_id=\"$container_id\",name=\"$name\"} $net_rx_bytes" >> ${STATS_FILE}
            echo "docker_container_network_tx_bytes{container_id=\"$container_id\",name=\"$name\"} $net_tx_bytes" >> ${STATS_FILE}
            echo "docker_container_pids{container_id=\"$container_id\",name=\"$name\"} $pids" >> ${STATS_FILE}
        fi
    done
}

# Function to serve metrics
serve_metrics() {
    while true; do
        collect_stats
        sleep 15
    done
}

# Main
case "${1}" in
    collect)
        collect_stats
        cat ${STATS_FILE}
        ;;
    serve)
        echo "Starting Docker Stats Collector on port ${STATS_PORT}..."
        serve_metrics &

        # Simple HTTP server to serve metrics
        while true; do
            { echo -ne "HTTP/1.1 200 OK\r\nContent-Length: $(wc -c <${STATS_FILE})\r\n\r\n"; cat ${STATS_FILE}; } | nc -l -p ${STATS_PORT} -q 1
        done
        ;;
    *)
        echo "Usage: $0 {collect|serve}"
        echo "  collect - Collect and display stats once"
        echo "  serve   - Start HTTP server on port ${STATS_PORT}"
        exit 1
        ;;
esac