#!/usr/bin/env python3

import os
import subprocess
import time
import requests
import json
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
import docker
import re

class MultiExporter:
    def __init__(self):
        self.metrics_data = {}
        self.lock = threading.Lock()
        self.nfs_mount_path = "/var/www/html/nfs"
        self.nfs_server = "192.168.0.200"
        self.haproxy_stats_url = "http://haproxy:8404/stats;csv"

        # Docker client
        try:
            self.docker_client = docker.from_env()
        except Exception as e:
            print(f"Docker client initialization failed: {e}")
            self.docker_client = None

    # NFS Monitoring
    def check_nfs_mount_status(self):
        """Check if NFS is mounted and accessible"""
        try:
            # Check if mount path exists
            if not os.path.exists(self.nfs_mount_path):
                return 0, 0, 0

            # Check mount status by reading /proc/mounts
            is_mounted = 0
            try:
                with open('/proc/mounts', 'r') as f:
                    mounts = f.read()
                    if self.nfs_server in mounts and self.nfs_mount_path in mounts:
                        is_mounted = 1
            except:
                # Fallback to mountpoint command
                result = subprocess.run(['mountpoint', '-q', self.nfs_mount_path],
                                      capture_output=True)
                is_mounted = 1 if result.returncode == 0 else 0

            read_time = 0
            write_time = 0

            if is_mounted:
                test_file = os.path.join(self.nfs_mount_path, '.nfs_test')
                try:
                    start_time = time.time()
                    with open(test_file, 'w') as f:
                        f.write('test' * 1000)
                    write_time = (time.time() - start_time) * 1000

                    start_time = time.time()
                    with open(test_file, 'r') as f:
                        f.read()
                    read_time = (time.time() - start_time) * 1000

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
        """Check NFS server connectivity and service"""
        try:
            # First check if server is reachable
            ping_result = subprocess.run(['ping', '-c', '1', '-W', '2', self.nfs_server],
                                       capture_output=True)
            if ping_result.returncode != 0:
                print(f"NFS server {self.nfs_server} not pingable")
                return 0

            # Check if we can get NFS exports list (best way to verify NFS service)
            try:
                # Try showmount -e to check NFS exports
                showmount_result = subprocess.run(
                    ['showmount', '-e', self.nfs_server],
                    capture_output=True,
                    timeout=3
                )
                if showmount_result.returncode == 0:
                    print(f"NFS server {self.nfs_server} is running and accessible")
                    return 1
                else:
                    # If showmount fails, try socket connection as fallback
                    import socket
                    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                    sock.settimeout(2)
                    try:
                        result = sock.connect_ex((self.nfs_server, 2049))
                        sock.close()
                        if result == 0:
                            print(f"NFS port 2049 open on {self.nfs_server}, but showmount failed")
                            return 0  # Port open but NFS service might not be running properly
                        else:
                            print(f"NFS port 2049 closed on {self.nfs_server}")
                            return 0
                    except:
                        return 0
            except subprocess.TimeoutExpired:
                print(f"showmount timeout for {self.nfs_server}")
                return 0
            except FileNotFoundError:
                # showmount not installed, use socket check
                import socket
                sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                sock.settimeout(2)
                try:
                    result = sock.connect_ex((self.nfs_server, 2049))
                    sock.close()
                    return 0  # Can't verify NFS properly without showmount
                except:
                    return 0
        except Exception as e:
            print(f"NFS connectivity check error: {e}")
            return 0

    # HAProxy Monitoring
    def get_haproxy_stats(self):
        """Get HAProxy statistics"""
        try:
            response = requests.get(self.haproxy_stats_url, timeout=5)
            if response.status_code != 200:
                return {}

            lines = response.text.strip().split('\n')
            headers = lines[0].split(',')
            stats = {}

            for line in lines[1:]:
                if not line or line.startswith('#'):
                    continue

                values = line.split(',')
                if len(values) < len(headers):
                    continue

                row = dict(zip(headers, values))

                # Skip non-server entries
                if row.get('type') != '2':  # type 2 = server
                    continue

                server_name = f"{row.get('pxname', '')}/{row.get('svname', '')}"

                # Response time metrics
                response_time = row.get('rtime', '')
                if response_time and response_time != '':
                    try:
                        stats[f'haproxy_response_time_ms{{server="{server_name}"}}'] = float(response_time)
                    except ValueError:
                        pass

                # Session rate
                session_rate = row.get('rate', '')
                if session_rate and session_rate != '':
                    try:
                        stats[f'haproxy_session_rate{{server="{server_name}"}}'] = float(session_rate)
                    except ValueError:
                        pass

                # Queue time
                queue_time = row.get('qtime', '')
                if queue_time and queue_time != '':
                    try:
                        stats[f'haproxy_queue_time_ms{{server="{server_name}"}}'] = float(queue_time)
                    except ValueError:
                        pass

                # Connection time
                connect_time = row.get('ctime', '')
                if connect_time and connect_time != '':
                    try:
                        stats[f'haproxy_connect_time_ms{{server="{server_name}"}}'] = float(connect_time)
                    except ValueError:
                        pass

            return stats

        except Exception as e:
            print(f"Failed to get HAProxy stats: {e}")
            return {}

    # MySQL Monitoring (via Docker logs parsing)
    def get_mysql_stats(self):
        """Get basic MySQL stats from container"""
        try:
            if not self.docker_client:
                return {}

            mysql_container = self.docker_client.containers.get('mysql')

            # Check if container is running
            if mysql_container.status != 'running':
                return {'mysql_up': 0}

            stats = {'mysql_up': 1}

            # Try to get connection count via docker exec
            try:
                result = mysql_container.exec_run(
                    "mysql -u root -pnaver123 -e \"SHOW STATUS LIKE 'Threads_connected';\" testdb"
                )
                if result.exit_code == 0:
                    output = result.output.decode('utf-8')
                    # Parse the output to get connection count
                    for line in output.split('\n'):
                        if 'Threads_connected' in line:
                            parts = line.split()
                            if len(parts) >= 2:
                                try:
                                    stats['mysql_connections'] = float(parts[-1])
                                except ValueError:
                                    pass
            except Exception as e:
                print(f"Failed to get MySQL connection count: {e}")

            # Get queries per second from SHOW STATUS
            try:
                result = mysql_container.exec_run(
                    "mysql -u root -pnaver123 -e \"SHOW STATUS LIKE 'Queries';\" testdb"
                )
                if result.exit_code == 0:
                    output = result.output.decode('utf-8')
                    for line in output.split('\n'):
                        if 'Queries' in line and 'Queries' == line.split()[0]:
                            parts = line.split()
                            if len(parts) >= 2:
                                try:
                                    stats['mysql_queries_total'] = float(parts[-1])
                                except ValueError:
                                    pass
            except Exception as e:
                print(f"Failed to get MySQL query count: {e}")

            return stats

        except Exception as e:
            print(f"Failed to get MySQL stats: {e}")
            return {'mysql_up': 0}

    def collect_metrics(self):
        """Collect all metrics"""
        with self.lock:
            self.metrics_data = {}

            # NFS metrics
            is_mounted, read_time, write_time = self.check_nfs_mount_status()
            server_reachable = self.check_nfs_server_connectivity()

            self.metrics_data.update({
                'nfs_mount_status': is_mounted,
                'nfs_server_reachable': server_reachable,
                'nfs_read_latency_ms': read_time if read_time >= 0 else 0,
                'nfs_write_latency_ms': write_time if write_time >= 0 else 0,
            })

            # HAProxy metrics
            haproxy_stats = self.get_haproxy_stats()
            self.metrics_data.update(haproxy_stats)

            # MySQL metrics
            mysql_stats = self.get_mysql_stats()
            self.metrics_data.update(mysql_stats)

    def get_prometheus_metrics(self):
        """Format metrics in Prometheus format"""
        with self.lock:
            lines = []

            # Help comments
            lines.extend([
                "# HELP nfs_mount_status NFS mount status (1=mounted, 0=not mounted)",
                "# TYPE nfs_mount_status gauge",
                "# HELP nfs_server_reachable NFS server reachability",
                "# TYPE nfs_server_reachable gauge",
                "# HELP nfs_read_latency_ms NFS read latency in milliseconds",
                "# TYPE nfs_read_latency_ms gauge",
                "# HELP nfs_write_latency_ms NFS write latency in milliseconds",
                "# TYPE nfs_write_latency_ms gauge",
                "# HELP haproxy_response_time_ms HAProxy backend response time",
                "# TYPE haproxy_response_time_ms gauge",
                "# HELP haproxy_session_rate HAProxy session rate",
                "# TYPE haproxy_session_rate gauge",
                "# HELP haproxy_queue_time_ms HAProxy queue time",
                "# TYPE haproxy_queue_time_ms gauge",
                "# HELP haproxy_connect_time_ms HAProxy connect time",
                "# TYPE haproxy_connect_time_ms gauge",
                "# HELP mysql_up MySQL server status",
                "# TYPE mysql_up gauge",
                "# HELP mysql_connections Current MySQL connections",
                "# TYPE mysql_connections gauge",
                "# HELP mysql_queries_total Total MySQL queries",
                "# TYPE mysql_queries_total counter",
            ])

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
        pass


def main():
    exporter = MultiExporter()

    def collect_loop():
        while True:
            try:
                exporter.collect_metrics()
                time.sleep(30)
            except Exception as e:
                print(f"Error in collection loop: {e}")
                time.sleep(10)

    collector_thread = threading.Thread(target=collect_loop, daemon=True)
    collector_thread.start()

    def handler(*args, **kwargs):
        MetricsHandler(exporter, *args, **kwargs)

    server = HTTPServer(('0.0.0.0', 9170), handler)
    print("Multi Exporter starting on port 9170...")
    print("Metrics available at http://localhost:9170/metrics")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("Shutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()