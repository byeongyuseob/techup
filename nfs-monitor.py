#!/usr/bin/env python3

import os
import subprocess
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading

class NFSMonitor:
    def __init__(self):
        self.metrics_data = {}
        self.lock = threading.Lock()
        self.nfs_mount_path = "/var/www/html/nfs"
        self.nfs_server = "10.95.137.10"

    def check_nfs_mount_status(self):
        """Check if NFS is mounted and accessible"""
        try:
            # Check if mount point exists
            if not os.path.exists(self.nfs_mount_path):
                return 0, 0, 0

            # Check if actually mounted
            result = subprocess.run(['mountpoint', '-q', self.nfs_mount_path],
                                  capture_output=True)
            is_mounted = 1 if result.returncode == 0 else 0

            # Test read/write performance if mounted
            read_time = 0
            write_time = 0

            if is_mounted:
                # Test write performance
                test_file = os.path.join(self.nfs_mount_path, '.nfs_test')
                try:
                    start_time = time.time()
                    with open(test_file, 'w') as f:
                        f.write('test' * 1000)  # 4KB test file
                    write_time = (time.time() - start_time) * 1000  # ms

                    # Test read performance
                    start_time = time.time()
                    with open(test_file, 'r') as f:
                        f.read()
                    read_time = (time.time() - start_time) * 1000  # ms

                    os.remove(test_file)
                except Exception as e:
                    print(f"NFS performance test failed: {e}")
                    read_time = -1
                    write_time = -1

            return is_mounted, read_time, write_time

        except Exception as e:
            print(f"NFS mount check failed: {e}")
            return 0, -1, -1

    def check_nfs_server_connectivity(self):
        """Check NFS server connectivity"""
        try:
            result = subprocess.run(['ping', '-c', '1', '-W', '2', self.nfs_server],
                                  capture_output=True)
            return 1 if result.returncode == 0 else 0
        except Exception:
            return 0

    def get_nfs_stats(self):
        """Get NFS statistics from /proc/net/rpc/nfs"""
        try:
            with open('/proc/net/rpc/nfs', 'r') as f:
                content = f.read()

            stats = {}
            for line in content.split('\n'):
                if line.startswith('proc3'):
                    # NFSv3 procedure statistics
                    parts = line.split()
                    if len(parts) >= 25:  # read and write are at positions 7 and 8
                        stats['read_ops'] = int(parts[7])
                        stats['write_ops'] = int(parts[8])
                        break

            return stats.get('read_ops', 0), stats.get('write_ops', 0)

        except Exception as e:
            print(f"Failed to read NFS stats: {e}")
            return 0, 0

    def collect_metrics(self):
        """Collect NFS metrics"""
        with self.lock:
            # Mount status and performance
            is_mounted, read_time, write_time = self.check_nfs_mount_status()
            server_reachable = self.check_nfs_server_connectivity()
            read_ops, write_ops = self.get_nfs_stats()

            self.metrics_data = {
                'nfs_mount_status': is_mounted,
                'nfs_server_reachable': server_reachable,
                'nfs_read_latency_ms': read_time if read_time >= 0 else 0,
                'nfs_write_latency_ms': write_time if write_time >= 0 else 0,
                'nfs_read_ops_total': read_ops,
                'nfs_write_ops_total': write_ops
            }

    def get_prometheus_metrics(self):
        """Format metrics in Prometheus format"""
        with self.lock:
            lines = []

            # Add help and type comments
            lines.append("# HELP nfs_mount_status NFS mount status (1=mounted, 0=not mounted)")
            lines.append("# TYPE nfs_mount_status gauge")
            lines.append("# HELP nfs_server_reachable NFS server reachability (1=reachable, 0=not reachable)")
            lines.append("# TYPE nfs_server_reachable gauge")
            lines.append("# HELP nfs_read_latency_ms NFS read latency in milliseconds")
            lines.append("# TYPE nfs_read_latency_ms gauge")
            lines.append("# HELP nfs_write_latency_ms NFS write latency in milliseconds")
            lines.append("# TYPE nfs_write_latency_ms gauge")
            lines.append("# HELP nfs_read_ops_total Total NFS read operations")
            lines.append("# TYPE nfs_read_ops_total counter")
            lines.append("# HELP nfs_write_ops_total Total NFS write operations")
            lines.append("# TYPE nfs_write_ops_total counter")

            # Add metrics
            for metric, value in self.metrics_data.items():
                lines.append(f"{metric} {value}")

            return '\n'.join(lines)


class MetricsHandler(BaseHTTPRequestHandler):
    def __init__(self, nfs_monitor, *args, **kwargs):
        self.nfs_monitor = nfs_monitor
        super().__init__(*args, **kwargs)

    def do_GET(self):
        if self.path == '/metrics':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain; version=0.0.4; charset=utf-8')
            self.end_headers()

            metrics = self.nfs_monitor.get_prometheus_metrics()
            self.wfile.write(metrics.encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        # Suppress default logging
        pass


def main():
    nfs_monitor = NFSMonitor()

    # Start metrics collection in background
    def collect_loop():
        while True:
            try:
                nfs_monitor.collect_metrics()
                time.sleep(30)  # Collect every 30 seconds
            except Exception as e:
                print(f"Error in collection loop: {e}")
                time.sleep(10)

    collector_thread = threading.Thread(target=collect_loop, daemon=True)
    collector_thread.start()

    # Create HTTP server
    def handler(*args, **kwargs):
        MetricsHandler(nfs_monitor, *args, **kwargs)

    server = HTTPServer(('0.0.0.0', 9160), handler)
    print("NFS Monitor starting on port 9160...")
    print("Metrics available at http://localhost:9160/metrics")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Shutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()