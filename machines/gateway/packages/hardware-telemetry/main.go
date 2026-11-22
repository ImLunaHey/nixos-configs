package main

import (
	"context"
	"encoding/csv"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/disk"
	"github.com/shirou/gopsutil/v4/host"
	"github.com/shirou/gopsutil/v4/load"
	"github.com/shirou/gopsutil/v4/mem"
	gnet "github.com/shirou/gopsutil/v4/net"
	"os/exec"
)

type M = map[string]any

var mu sync.RWMutex
var snapshot M
var peers = map[string]M{}
var peerURLs = map[string]string{}
var client = &http.Client{Timeout: 3 * time.Second}
var zfsSnapshot M

func env(k, fallback string) string {
	if s := os.Getenv(k); s != "" {
		return s
	}
	return fallback
}
func command(name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, name, args...).Output()
}
func num(s string) any {
	n, e := strconv.ParseFloat(strings.TrimSpace(s), 64)
	if e != nil || math.IsNaN(n) || math.IsInf(n, 0) {
		return nil
	}
	return n
}
func readNum(path string, scale float64) any {
	b, e := os.ReadFile(path)
	if e != nil {
		return nil
	}
	n := num(string(b))
	if n == nil {
		return nil
	}
	return n.(float64) / scale
}
func val(m M, k string) float64 {
	if n, ok := m[k].(float64); ok {
		return n
	}
	return 0
}
func fresh(m M) bool {
	return m != nil && val(m, "timestamp") > 0 && math.Abs(float64(time.Now().Unix())-val(m, "timestamp")) < 12
}
func pollPeer(name, url string) {
	for {
		var data M
		online := false
		if url != "" {
			r, e := client.Get(url)
			if e == nil {
				if r.StatusCode == 200 {
					e = json.NewDecoder(io.LimitReader(r.Body, 1<<20)).Decode(&data)
					online = e == nil && fresh(data)
				}
				r.Body.Close()
			}
		}
		if !online {
			data = nil
		}
		mu.Lock()
		peers[name] = M{"online": online, "metrics": data}
		mu.Unlock()
		time.Sleep(2 * time.Second)
	}
}
func gpu() M {
	if runtime.GOOS == "darwin" {
		return appleGPU()
	}
	if os.Getenv("AMD_GPU_NAME") != "" {
		paths, _ := filepath.Glob("/sys/class/drm/card[0-9]*/device")
		for _, p := range paths {
			b, _ := os.ReadFile(p + "/vendor")
			if strings.TrimSpace(string(b)) != "0x1002" {
				continue
			}
			h, _ := filepath.Glob(p + "/hwmon/hwmon*")
			var temp, clock any
			if len(h) > 0 {
				temp = readNum(h[0]+"/temp1_input", 1000)
				clock = readNum(h[0]+"/freq1_input", 1000000)
			}
			return M{"name": os.Getenv("AMD_GPU_NAME"), "kind": "integrated", "usage": readNum(p+"/gpu_busy_percent", 1), "temperature": temp, "core_clock": clock, "memory_used": readNum(p+"/mem_info_vram_used", 1048576), "memory_total": readNum(p+"/mem_info_vram_total", 1048576), "memory_label": "Reserved UMA", "power": nil, "fan": nil}
		}
		return nil
	}
	if runtime.GOOS != "linux" {
		return nil
	}
	b, e := command(env("NVIDIA_SMI", "nvidia-smi"), "--query-gpu=name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,power.limit,utilization.memory,fan.speed,clocks.gr,clocks.mem,pstate", "--format=csv,noheader,nounits")
	if e != nil {
		return otherGPU()
	}
	r := csv.NewReader(strings.NewReader(string(b)))
	r.TrimLeadingSpace = true
	row, e := r.Read()
	if e != nil || len(row) != 12 {
		return otherGPU()
	}
	keys := []string{"name", "usage", "memory_used", "memory_total", "temperature", "power", "power_limit", "memory_usage", "fan", "core_clock", "memory_clock", "state"}
	m := M{"kind": "discrete", "memory_label": "VRAM"}
	for i, k := range keys {
		if i == 0 || i == 11 {
			m[k] = row[i]
		} else {
			m[k] = num(row[i])
		}
	}
	return m
}
func temperatures() any {
	paths, _ := filepath.Glob("/sys/class/hwmon/hwmon*")
	for _, p := range paths {
		b, _ := os.ReadFile(p + "/name")
		name := strings.TrimSpace(string(b))
		if name == "k10temp" || name == "coretemp" {
			return readNum(p+"/temp1_input", 1000)
		}
	}
	return nil
}
func sensorLines() M {
	p := os.Getenv("METRICS_SENSOR_FILE")
	if p == "" {
		return nil
	}
	fi, e := os.Stat(p)
	if e != nil || time.Since(fi.ModTime()) > 120*time.Second {
		return M{"status": "Sensor readings unavailable or stale"}
	}
	b, e := os.ReadFile(p)
	if e != nil {
		return nil
	}
	m := M{}
	for _, line := range strings.Split(string(b), "\n") {
		kv := strings.SplitN(strings.TrimSpace(line), ": ", 2)
		if len(kv) == 2 {
			m[kv[0]] = kv[1]
		}
	}
	return m
}
func healthy(url string) bool {
	r, e := client.Get(url)
	if e != nil {
		return false
	}
	r.Body.Close()
	return r.StatusCode == 200
}
func diskDevice() string {
	if d := os.Getenv("METRICS_DISK"); d != "" {
		return d
	}
	parts, _ := disk.Partitions(false)
	for _, p := range parts {
		if p.Mountpoint == "/" {
			dev := p.Device
			if resolved, e := filepath.EvalSymlinks(dev); e == nil {
				dev = resolved
			}
			name := filepath.Base(dev)
			block := "/sys/class/block/" + name
			if _, e := os.Stat(block + "/partition"); e == nil {
				if resolved, e := filepath.EvalSymlinks(block); e == nil {
					name = filepath.Base(filepath.Dir(resolved))
				}
			}
			return name
		}
	}
	return "unknown"
}
func network(name string) (gnet.IOCountersStat, string) {
	all, _ := gnet.IOCounters(true)
	var counter gnet.IOCountersStat
	for _, c := range all {
		if c.Name == name {
			counter = c
		}
	}
	address := "Unavailable"
	if iface, e := net.InterfaceByName(name); e == nil {
		addresses, _ := iface.Addrs()
		for _, a := range addresses {
			ip, _, _ := net.ParseCIDR(a.String())
			if ip != nil && ip.To4() != nil {
				address = ip.String()
				break
			}
		}
	}
	return counter, address
}
func rate(current, previous uint64, elapsed float64) float64 {
	if current < previous || elapsed <= 0 {
		return 0
	}
	return float64(current-previous) / elapsed
}
func sample() {
	name, _ := os.Hostname()
	name = env("METRICS_NAME", strings.Split(name, ".")[0])
	iface := env("METRICS_INTERFACE", "en0")
	device := diskDevice()
	info, _ := cpu.Info()
	model := "Unknown CPU"
	if len(info) > 0 {
		model = info[0].ModelName
	}
	physical, _ := cpu.Counts(false)
	prevNet, _ := network(iface)
	allDisk, _ := disk.IOCounters()
	prevDisk := allDisk[device]
	previous := time.Now()
	cpu.Percent(0, true)
	services := M{}
	iteration := 0
	for {
		start := time.Now()
		cores, e := cpu.Percent(0, true)
		if e != nil || len(cores) == 0 {
			time.Sleep(2 * time.Second)
			continue
		}
		memory, e := mem.VirtualMemory()
		if e != nil {
			time.Sleep(2 * time.Second)
			continue
		}
		rootPath := "/"
		if runtime.GOOS == "darwin" {
			rootPath = "/System/Volumes/Data"
		}
		usage, e := disk.Usage(rootPath)
		if e != nil {
			time.Sleep(2 * time.Second)
			continue
		}
		up, _ := host.Uptime()
		total := 0.0
		for _, n := range cores {
			total += n
		}
		clock := 0.0
		ci, _ := cpu.Info()
		for _, c := range ci {
			clock += c.Mhz
		}
		if len(ci) > 0 {
			clock /= float64(len(ci))
		}
		loadavg, _ := load.Avg()
		loads := []float64{}
		if loadavg != nil {
			loads = []float64{loadavg.Load1, loadavg.Load5, loadavg.Load15}
		}
		currentNet, address := network(iface)
		elapsed := start.Sub(previous).Seconds()
		ios, _ := disk.IOCounters()
		currentDisk, hasDisk := ios[device]
		var read, write, iops any
		if hasDisk {
			read = rate(currentDisk.ReadBytes, prevDisk.ReadBytes, elapsed)
			write = rate(currentDisk.WriteBytes, prevDisk.WriteBytes, elapsed)
			iops = rate(currentDisk.ReadCount+currentDisk.WriteCount, prevDisk.ReadCount+prevDisk.WriteCount, elapsed)
		}
		var speed any = readNum("/sys/class/net/"+iface+"/speed", 1)
		if speed != nil && speed.(float64) < 0 {
			speed = nil
		}
		swap, _ := mem.SwapMemory()
		var swapUsed, swapTotal uint64
		if swap != nil {
			swapUsed = swap.Used
			swapTotal = swap.Total
		}
		if name == "tower" && iteration%5 == 0 {
			services = M{"inference": healthy("http://127.0.0.1:8080/health"), "workspace": healthy("http://127.0.0.1:3773/")}
		}
		data := M{"timestamp": float64(time.Now().UnixMilli()) / 1000, "host": name, "os": runtime.GOOS, "cpu_name": model, "physical_cores": physical, "interface": iface, "sensors": sensorLines(), "uptime": up, "cpu": M{"usage": total / float64(len(cores)), "cores": cores, "temperature": temperatures(), "frequency": clock, "load": loads}, "gpu": gpu(), "memory": M{"used": memory.Total - memory.Available, "total": memory.Total, "available": memory.Available, "percent": 100 * float64(memory.Total-memory.Available) / float64(memory.Total), "cached": memory.Cached, "buffers": memory.Buffers, "swap_used": swapUsed, "swap_total": swapTotal}, "disk": M{"used": usage.Used, "total": usage.Total, "free": usage.Free, "percent": usage.UsedPercent, "device": device, "read": read, "write": write, "iops": iops}, "network": M{"download": rate(currentNet.BytesRecv, prevNet.BytesRecv, elapsed), "upload": rate(currentNet.BytesSent, prevNet.BytesSent, elapsed), "received": currentNet.BytesRecv, "sent": currentNet.BytesSent, "address": address, "speed": speed, "connected": address != "Unavailable"}, "services": services}
		mu.Lock()
		data["zfs"] = zfsSnapshot
		snapshot = data
		mu.Unlock()
		previous = start
		prevNet = currentNet
		prevDisk = currentDisk
		iteration++
		if delay := 2*time.Second - time.Since(start); delay > 0 {
			time.Sleep(delay)
		}
	}
}
func zfsLoop() {
	for {
		data, e := collectZFS()
		mu.Lock()
		if e != nil {
			zfsSnapshot = M{"available": false, "error": "ZFS telemetry unavailable"}
		} else {
			zfsSnapshot = data
		}
		mu.Unlock()
		time.Sleep(10 * time.Second)
	}
}
func zfsDisks(node M, group string) []M {
	out := []M{}
	kind, _ := node["vdev_type"].(string)
	if kind == "disk" {
		out = append(out, M{"name": node["name"], "path": node["path"], "port": drivePort(node["phys_path"]), "state": node["state"], "size": node["phys_space"], "read_errors": node["read_errors"], "write_errors": node["write_errors"], "checksum_errors": node["checksum_errors"], "replacing": group == "replacing", "missing": node["not_present"], "resilvered": node["scan_processed"]})
	}
	children, _ := node["vdevs"].(map[string]any)
	for _, v := range children {
		if child, ok := v.(map[string]any); ok {
			out = append(out, zfsDisks(child, kind)...)
		}
	}
	return out
}
func parseZFS(status []byte, pool string) (M, error) {
	var doc M
	if e := json.Unmarshal(status, &doc); e != nil {
		return nil, e
	}
	pools, _ := doc["pools"].(map[string]any)
	p, ok := pools[pool].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("pool missing")
	}
	vdevs, _ := p["vdevs"].(map[string]any)
	root, _ := vdevs[pool].(map[string]any)
	if root == nil {
		return nil, fmt.Errorf("root missing")
	}
	scan, _ := p["scan_stats"].(map[string]any)
	var progress any
	if val(scan, "to_examine") > 0 {
		progress = math.Min(100, 100*val(scan, "issued")/val(scan, "to_examine"))
	}
	return M{"available": true, "timestamp": float64(time.Now().Unix()), "name": pool, "state": p["state"], "status": p["status"], "action": p["action"], "data_errors": p["error_count"], "raw_total": root["total_space"], "raw_used": root["alloc_space"], "read_errors": root["read_errors"], "write_errors": root["write_errors"], "checksum_errors": root["checksum_errors"], "scan": scan, "scan_percent": progress, "drives": zfsDisks(root, "")}, nil
}
func collectZFS() (M, error) {
	pool := env("METRICS_ZFS_POOL", "storage")
	b, e := command(env("ZPOOL", "zpool"), "status", "-j", "--json-int", pool)
	if e != nil {
		return nil, e
	}
	data, e := parseZFS(b, pool)
	if e != nil {
		return nil, e
	}
	b, e = command(env("ZFS", "zfs"), "list", "-Hp", "-o", "name,used,avail,refer,mountpoint", "-r", pool)
	if e != nil {
		return nil, e
	}
	datasets := []M{}
	for _, line := range strings.Split(strings.TrimSpace(string(b)), "\n") {
		fields := strings.Split(line, "\t")
		if len(fields) != 5 {
			continue
		}
		datasets = append(datasets, M{"name": fields[0], "used": num(fields[1]), "available": num(fields[2]), "referenced": num(fields[3]), "mount": fields[4]})
	}
	data["datasets"] = datasets
	addDriveStats(data)
	return data, nil
}
func main() {
	_ = json.Unmarshal([]byte(env("DASHBOARD_PEERS", "{}")), &peerURLs)
	go sample()
	if os.Getenv("METRICS_ZFS_POOL") != "" {
		go zfsLoop()
	}
	for name, url := range peerURLs {
		go pollPeer(name, url)
	}
	page, _ := os.ReadFile(os.Getenv("DASHBOARD_HTML"))
	allowed := map[string]bool{}
	for _, ip := range strings.Split(os.Getenv("METRICS_ALLOWED_CLIENTS"), ",") {
		if ip != "" {
			allowed[ip] = true
		}
	}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ip, _, _ := net.SplitHostPort(r.RemoteAddr)
		if len(allowed) > 0 && !allowed[ip] {
			http.Error(w, "Forbidden", 403)
			return
		}
		if r.Method != "GET" {
			http.Error(w, "Method not allowed", 405)
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		mu.RLock()
		defer mu.RUnlock()
		var data any
		switch {
		case r.URL.Path == "/" && len(page) > 0:
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			w.Write(page)
			return
		case r.URL.Path == "/api/metrics":
			data = snapshot
		case r.URL.Path == "/api/fleet" && len(page) > 0:
			name := env("METRICS_NAME", "tower")
			fleet := M{name: M{"online": fresh(snapshot), "metrics": snapshot}}
			for n := range peerURLs {
				p, ok := peers[n]
				if !ok {
					p = M{"online": false, "metrics": nil}
				}
				fleet[n] = p
			}
			data = fleet
		case strings.HasPrefix(r.URL.Path, "/api/peers/"):
			name := strings.TrimPrefix(r.URL.Path, "/api/peers/")
			if _, ok := peerURLs[name]; !ok {
				http.NotFound(w, r)
				return
			}
			p := peers[name]
			if p["online"] != true {
				http.Error(w, "Peer unavailable", 503)
				return
			}
			data = p["metrics"]
		default:
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		if e := json.NewEncoder(w).Encode(data); e != nil {
			log.Print(e)
		}
	})
	server := &http.Server{Addr: env("METRICS_BIND", "127.0.0.1") + ":8099", Handler: handler, ReadHeaderTimeout: 3 * time.Second, WriteTimeout: 5 * time.Second, IdleTimeout: 30 * time.Second}
	log.Fatal(server.ListenAndServe())
}
