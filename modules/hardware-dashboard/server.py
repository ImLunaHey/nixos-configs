"""Read-only hardware telemetry for Tower's local kiosk."""

import csv
import socket
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


PAGE = Path(os.environ["DASHBOARD_HTML"]).read_bytes() if "DASHBOARD_HTML" in os.environ else None
INTERFACE = os.environ.get("METRICS_INTERFACE", "enp7s0")
PEERS = json.loads(os.environ.get("DASHBOARD_PEERS", "{}"))
remote_snapshots = {}
CPU_NAME = next((line.split(":", 1)[1].strip() for line in Path("/proc/cpuinfo").read_text().splitlines() if line.startswith("model name")), "CPU")


def poll_peer(name, url):
    while True:
        try:
            with urlopen(url, timeout=2) as response:
                data = json.loads(response.read(1024 * 1024))
            if not isinstance(data.get("timestamp"), (int, float)) or abs(time.time() - data["timestamp"]) > 10:
                raise ValueError("stale telemetry")
            remote_snapshots[name] = {"online": True, "metrics": data}
        except (OSError, ValueError):
            remote_snapshots[name] = {"online": False, "metrics": None}
        time.sleep(2)


def sensor_lines():
    path = os.environ.get("METRICS_SENSOR_FILE")
    if not path:
        return None
    try:
        sensor_file = Path(path)
        if time.time() - sensor_file.stat().st_mtime > 120:
            return {"status": "Sensor readings are stale"}
        return dict(line.split(": ", 1) for line in sensor_file.read_text().splitlines() if ": " in line)
    except OSError:
        return {"status": "Sensor readings unavailable"}

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
             "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,utilization.memory,fan.speed,clocks.gr,clocks.mem,pstate",
             "--format=csv,noheader,nounits"],
            capture_output=True, text=True, check=True, timeout=2,
        )
        row = next(csv.reader(result.stdout.splitlines(), skipinitialspace=True))
        return dict(zip(
            ["name", "usage", "memory_used", "memory_total", "temperature", "power", "power_limit",
             "memory_usage", "fan", "core_clock", "memory_clock", "state"],
            [row[0]] + [number(value) for value in row[1:-1]] + [row[-1]],
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
    previous_network = psutil.net_io_counters(pernic=True).get(INTERFACE)
    previous_time = time.monotonic()
    root_partition = next(p.device for p in psutil.disk_partitions() if p.mountpoint == "/")
    root_block = Path("/sys/class/block") / Path(os.path.realpath(root_partition)).name
    root_device = root_block.resolve().parent.name if (root_block / "partition").exists() else root_block.name
    previous_disk = psutil.disk_io_counters(perdisk=True).get(root_device)
    services = {}
    iteration = 0
    psutil.cpu_percent(percpu=True)
    while True:
        started = time.monotonic()
        try:
            cores = psutil.cpu_percent(percpu=True)
            memory = psutil.virtual_memory()
            swap = psutil.swap_memory()
            disk = psutil.disk_usage("/")
            temperatures = psutil.sensors_temperatures()
            cpu_sensors = temperatures.get("k10temp", [])
            cpu_temperature = next((s.current for s in cpu_sensors if s.label == "Tctl"), None)
            if cpu_temperature is None and cpu_sensors:
                cpu_temperature = cpu_sensors[0].current
            frequency = psutil.cpu_freq()
            network = psutil.net_io_counters(pernic=True).get(INTERFACE)
            elapsed = max(started - previous_time, 0.001)
            rates = {"download": None, "upload": None}
            if network and previous_network:
                rates = {
                    "download": max(0, network.bytes_recv - previous_network.bytes_recv) / elapsed,
                    "upload": max(0, network.bytes_sent - previous_network.bytes_sent) / elapsed,
                }
            previous_network, previous_time = network, started
            disk_counters = psutil.disk_io_counters(perdisk=True).get(root_device)
            disk_rates = {"read": None, "write": None, "iops": None}
            if disk_counters and previous_disk:
                disk_rates = {
                    "read": max(0, disk_counters.read_bytes - previous_disk.read_bytes) / elapsed,
                    "write": max(0, disk_counters.write_bytes - previous_disk.write_bytes) / elapsed,
                    "iops": max(0, disk_counters.read_count + disk_counters.write_count
                                - previous_disk.read_count - previous_disk.write_count) / elapsed,
                }
            previous_disk = disk_counters
            processes = []
            for process in psutil.process_iter(["pid", "name", "cpu_percent", "memory_info"]):
                info = process.info
                if info["memory_info"] is not None and info["cpu_percent"] is not None:
                    processes.append({"pid": info["pid"], "name": info["name"],
                                      "cpu": info["cpu_percent"] / len(cores),
                                      "memory": info["memory_info"].rss})
            processes.sort(key=lambda p: (p["cpu"], p["memory"]), reverse=True)
            addresses = psutil.net_if_addrs().get(INTERFACE, [])
            address = next((a.address for a in addresses if a.family.name == "AF_INET"), "Offline")
            link = psutil.net_if_stats().get(INTERFACE)
            if iteration % 5 == 0:
                services = {
                    "inference": healthy("http://127.0.0.1:8080/health"),
                    "workspace": healthy("http://127.0.0.1:3773/"),
                }
            snapshot = {
                "timestamp": time.time(),
                "host": socket.gethostname(),
                "cpu_name": CPU_NAME,
                "physical_cores": psutil.cpu_count(logical=False),
                "interface": INTERFACE,
                "sensors": sensor_lines(),
                "uptime": time.time() - psutil.boot_time(),
                "cpu": {"usage": sum(cores) / len(cores), "cores": cores,
                        "temperature": cpu_temperature,
                        "frequency": frequency.current if frequency else None,
                        "load": psutil.getloadavg()},
                "gpu": gpu_metrics(),
                "memory": {"used": memory.total - memory.available,
                           "total": memory.total, "available": memory.available, "percent": memory.percent,
                           "cached": memory.cached, "buffers": memory.buffers,
                           "swap_used": swap.used, "swap_total": swap.total},
                "disk": {"used": disk.used, "total": disk.total, "free": disk.free, "percent": disk.percent,
                         "device": root_device, **disk_rates},
                "network": {**rates, "address": address,
                            "received": network.bytes_recv if network else None,
                            "sent": network.bytes_sent if network else None,
                            "speed": link.speed if link else None,
                            "connected": link.isup if link else False},
                "processes": processes[:8],
                "services": services,
            }
            iteration += 1
        except Exception as error:
            # Keep serving the last sample; clients visibly mark it stale.
            print(f"Telemetry sample failed: {type(error).__name__}: {error}", flush=True)
        time.sleep(max(0.1, 2 - (time.monotonic() - started)))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" and PAGE is not None:
            payload, content_type = PAGE, "text/html; charset=utf-8"
        elif self.path == "/api/fleet" and PAGE is not None:
            fleet = {socket.gethostname(): {"online": bool(snapshot) and time.time() - snapshot["timestamp"] < 10, "metrics": snapshot}}
            fleet.update({name: remote_snapshots.get(name, {"online": False, "metrics": None}) for name in PEERS})
            payload, content_type = json.dumps(fleet, allow_nan=False).encode(), "application/json"
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
    for name, url in PEERS.items():
        threading.Thread(target=poll_peer, args=(name, url), daemon=True).start()
    ThreadingHTTPServer((os.environ.get("METRICS_BIND", "127.0.0.1"), 8099), Handler).serve_forever()
