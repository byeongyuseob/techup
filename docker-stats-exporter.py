#!/usr/bin/env python3

import json
import subprocess
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import re

class DockerStatsExporter:
    def __init__(self):
        self.metrics_data = {}
        self.lock = threading.Lock()

    def get_docker_stats(self):
        """Get Docker container statistics"""
        try:
            # Get container stats in JSON format
            cmd = ["docker", "stats", "--no-stream", "--format", "json"]
            result = subprocess.run(cmd, capture_output=True, text=True, check=True)

            stats = []
            for line in result.stdout.strip().split('\n'):
                if line:
                    stats.append(json.loads(line))

            return stats
        except subprocess.CalledProcessError as e:
            print(f"Error getting docker stats: {e}")
            return []
        except json.JSONDecodeError as e:
            print(f"Error parsing docker stats JSON: {e}")
            return []

    def parse_percentage(self, value):
        """Parse percentage string to float"""
        if '%' in value:
            return float(value.replace('%', ''))
        return 0.0

    def parse_memory(self, mem_str):
        """Parse memory string (e.g., '1.5GiB') to bytes"""
        mem_str = mem_str.strip()
        multipliers = {
            'B': 1,
            'KiB': 1024,
            'MiB': 1024**2,
            'GiB': 1024**3,
            'TiB': 1024**4,
            'KB': 1000,
            'MB': 1000**2,
            'GB': 1000**3,
            'TB': 1000**4
        }

        for unit, multiplier in multipliers.items():
            if mem_str.endswith(unit):
                try:
                    return float(mem_str[:-len(unit)]) * multiplier
                except ValueError:
                    return 0

        # Try to parse as plain number (bytes)
        try:
            return float(mem_str)
        except ValueError:
            return 0

    def parse_network_io(self, io_str):
        """Parse network I/O string"""
        if '/' in io_str:
            parts = io_str.split('/')
            if len(parts) == 2:
                rx = self.parse_memory(parts[0].strip())
                tx = self.parse_memory(parts[1].strip())
                return rx, tx
        return 0, 0

    def parse_block_io(self, io_str):
        """Parse block I/O string"""
        if '/' in io_str:
            parts = io_str.split('/')
            if len(parts) == 2:
                read = self.parse_memory(parts[0].strip())
                write = self.parse_memory(parts[1].strip())
                return read, write
        return 0, 0

    def collect_metrics(self):
        """Collect and format metrics for Prometheus"""
        stats = self.get_docker_stats()

        with self.lock:
            self.metrics_data = {}

            for stat in stats:
                container_name = stat.get('Name', 'unknown')
                container_id = stat.get('ID', 'unknown')[:12]  # Short ID

                # CPU usage
                cpu_percent = self.parse_percentage(stat.get('CPUPerc', '0%'))
                self.metrics_data[f'docker_cpu_usage_percent{{container="{container_name}",id="{container_id}"}}'] = cpu_percent

                # Memory usage
                mem_usage_str = stat.get('MemUsage', '0B / 0B')
                if '/' in mem_usage_str:
                    used, limit = mem_usage_str.split('/')
                    mem_used = self.parse_memory(used.strip())
                    mem_limit = self.parse_memory(limit.strip())

                    self.metrics_data[f'docker_memory_usage_bytes{{container="{container_name}",id="{container_id}"}}'] = mem_used
                    self.metrics_data[f'docker_memory_limit_bytes{{container="{container_name}",id="{container_id}"}}'] = mem_limit

                    if mem_limit > 0:
                        mem_percent = (mem_used / mem_limit) * 100
                        self.metrics_data[f'docker_memory_usage_percent{{container="{container_name}",id="{container_id}"}}'] = mem_percent

                # Memory percentage from docker stats
                mem_percent = self.parse_percentage(stat.get('MemPerc', '0%'))
                if mem_percent > 0:
                    self.metrics_data[f'docker_memory_percent{{container="{container_name}",id="{container_id}"}}'] = mem_percent

                # Network I/O
                net_io = stat.get('NetIO', '0B / 0B')
                net_rx, net_tx = self.parse_network_io(net_io)
                self.metrics_data[f'docker_network_rx_bytes{{container="{container_name}",id="{container_id}"}}'] = net_rx
                self.metrics_data[f'docker_network_tx_bytes{{container="{container_name}",id="{container_id}"}}'] = net_tx

                # Block I/O
                block_io = stat.get('BlockIO', '0B / 0B')
                block_read, block_write = self.parse_block_io(block_io)
                self.metrics_data[f'docker_block_read_bytes{{container="{container_name}",id="{container_id}"}}'] = block_read
                self.metrics_data[f'docker_block_write_bytes{{container="{container_name}",id="{container_id}"}}'] = block_write

                # PIDs
                pids = stat.get('PIDs', '0')
                try:
                    pids_count = int(pids)
                    self.metrics_data[f'docker_pids{{container="{container_name}",id="{container_id}"}}'] = pids_count
                except ValueError:
                    pass

    def get_prometheus_metrics(self):
        """Format metrics in Prometheus format"""
        with self.lock:
            lines = []

            # Add help and type comments
            lines.append("# HELP docker_cpu_usage_percent CPU usage percentage")
            lines.append("# TYPE docker_cpu_usage_percent gauge")
            lines.append("# HELP docker_memory_usage_bytes Memory usage in bytes")
            lines.append("# TYPE docker_memory_usage_bytes gauge")
            lines.append("# HELP docker_memory_limit_bytes Memory limit in bytes")
            lines.append("# TYPE docker_memory_limit_bytes gauge")
            lines.append("# HELP docker_memory_usage_percent Memory usage percentage")
            lines.append("# TYPE docker_memory_usage_percent gauge")
            lines.append("# HELP docker_network_rx_bytes Network bytes received")
            lines.append("# TYPE docker_network_rx_bytes counter")
            lines.append("# HELP docker_network_tx_bytes Network bytes transmitted")
            lines.append("# TYPE docker_network_tx_bytes counter")
            lines.append("# HELP docker_block_read_bytes Block I/O bytes read")
            lines.append("# TYPE docker_block_read_bytes counter")
            lines.append("# HELP docker_block_write_bytes Block I/O bytes written")
            lines.append("# TYPE docker_block_write_bytes counter")
            lines.append("# HELP docker_pids Number of PIDs")
            lines.append("# TYPE docker_pids gauge")

            # Add metrics
            for metric, value in self.metrics_data.items():
                lines.append(f"{metric} {value}")

            return '\n'.join(lines)


class MetricsHandler(BaseHTTPRequestHandler):
    def __init__(self, exporter, *args, **kwargs):
        self.exporter = exporter
        super().__init__(*args, **kwargs)

    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain; version=0.0.4; charset=utf-8')
            self.end_headers()

            metrics = self.exporter.get_prometheus_metrics()
            self.wfile.write(metrics.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress default logging
        pass


def main():
    exporter = DockerStatsExporter()

    # Start metrics collection in background
    def collect_loop():
        while True:
            try:
                exporter.collect_metrics()
                time.sleep(30)  # Collect every 30 seconds
            except Exception as e:
                print(f"Error in collection loop: {e}")
                time.sleep(10)

    collector_thread = threading.Thread(target=collect_loop, daemon=True)
    collector_thread.start()

    # Create HTTP server
    def handler(*args, **kwargs):
        MetricsHandler(exporter, *args, **kwargs)

    server = HTTPServer(('0.0.0.0', 9150), handler)
    print("Docker Stats Exporter starting on port 9150...")
    print("Metrics available at http://localhost:9150/metrics")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Shutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()