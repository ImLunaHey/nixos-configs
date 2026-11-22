"""Read-only hardware telemetry for Tower's local kiosk."""

import csv
import json
import math
import os
from pathlib import Path
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.request import urlopen

import psutil


PAGE = Path(os.environ.get("DASHBOARD_HTML", Path(__file__).with_name("index.html"))).read_bytes()
snapshot = {}


def number(value):
    try:
        parsed = float(value)
        return parsed if math.isfinite(parsed) else None
    except ValueError:
        return None


def gpu_metrics():
    try:
        result = subprocess.run(
            [os.environ.get("NVIDIA_SMI", "nvidia-smi"),
             "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, check=True, timeout=2,
        )
        row = next(csv.reader(result.stdout.splitlines(), skipinitialspace=True))
        return dict(zip(
            ["name", "usage", "memory_used", "memory_total", "temperature", "power", "power_limit"],
            [row[0]] + [number(value) for value in row[1:]],
        ))
    except (OSError, subprocess.SubprocessError, StopIteration):
        return None


def healthy(url):
    try:
        with urlopen(url, timeout=0.8) as response:
            return response.status == 200
    except OSError:
        return False


def sample_forever():
    global snapshot
    previous_network = psutil.net_io_counters(pernic=True).get("enp7s0")
    previous_time = time.monotonic()
    services = {}
    iteration = 0
    psutil.cpu_percent(percpu=True)
    while True:
        started = time.monotonic()
        try:
            cores = psutil.cpu_percent(percpu=True)
            memory = psutil.virtual_memory()
            disk = psutil.disk_usage("/")
            cpu_sensors = psutil.sensors_temperatures().get("k10temp", [])
            cpu_temperature = next((s.current for s in cpu_sensors if s.label == "Tctl"), None)
            if cpu_temperature is None and cpu_sensors:
                cpu_temperature = cpu_sensors[0].current
            frequency = psutil.cpu_freq()
            network = psutil.net_io_counters(pernic=True).get("enp7s0")
            elapsed = max(started - previous_time, 0.001)
            rates = {"download": None, "upload": None}
            if network and previous_network:
                rates = {
                    "download": max(0, network.bytes_recv - previous_network.bytes_recv) / elapsed,
                    "upload": max(0, network.bytes_sent - previous_network.bytes_sent) / elapsed,
                }
            previous_network, previous_time = network, started
            addresses = psutil.net_if_addrs().get("enp7s0", [])
            address = next((a.address for a in addresses if a.family.name == "AF_INET"), "Offline")
            if iteration % 5 == 0:
                services = {
                    "inference": healthy("http://127.0.0.1:8080/health"),
                    "workspace": healthy("http://127.0.0.1:3773/"),
                }
            snapshot = {
                "timestamp": time.time(),
                "uptime": time.time() - psutil.boot_time(),
                "cpu": {"usage": sum(cores) / len(cores), "cores": cores,
                        "temperature": cpu_temperature,
                        "frequency": frequency.current if frequency else None},
                "gpu": gpu_metrics(),
                "memory": {"used": memory.total - memory.available,
                           "total": memory.total, "available": memory.available, "percent": memory.percent},
                "disk": {"used": disk.used, "total": disk.total, "free": disk.free, "percent": disk.percent},
                "network": {**rates, "address": address},
                "services": services,
            }
            iteration += 1
        except Exception as error:
            # Keep serving the last sample; clients visibly mark it stale.
            print(f"Telemetry sample failed: {type(error).__name__}: {error}", flush=True)
        time.sleep(max(0.1, 2 - (time.monotonic() - started)))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/":
            payload, content_type = PAGE, "text/html; charset=utf-8"
        elif self.path == "/api/metrics":
            payload, content_type = json.dumps(snapshot, allow_nan=False).encode(), "application/json"
        else:
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_args):
        pass


if __name__ == "__main__":
    threading.Thread(target=sample_forever, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", 8099), Handler).serve_forever()
