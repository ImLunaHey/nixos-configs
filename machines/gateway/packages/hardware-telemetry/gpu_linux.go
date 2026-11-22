package main

import (
	"encoding/binary"
	"golang.org/x/sys/unix"
	"math"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"unsafe"
)

type engineCounter struct {
	fd             int
	value, enabled uint64
	ready          bool
}

var engines = map[string]*engineCounter{}

// i915 PMU engine-busy events count nanoseconds. Use the busiest engine,
// rather than adding concurrent render/video/blitter loads above 100%.
func intelUsage() (any, M) {
	paths, _ := filepath.Glob("/sys/bus/event_source/devices/i915/events/*-busy")
	typBytes, e := os.ReadFile("/sys/bus/event_source/devices/i915/type")
	if e != nil {
		return nil, nil
	}
	typ, e := strconv.ParseUint(strings.TrimSpace(string(typBytes)), 10, 32)
	if e != nil {
		return nil, nil
	}
	cpuID := 0
	if b, e := os.ReadFile("/sys/bus/event_source/devices/i915/cpumask"); e == nil {
		cpuID, _ = strconv.Atoi(strings.FieldsFunc(strings.TrimSpace(string(b)), func(r rune) bool { return r == ',' || r == '-' })[0])
	}
	values := M{}
	var max any
	for _, p := range paths {
		c := engines[p]
		if c == nil {
			b, e := os.ReadFile(p)
			if e != nil {
				continue
			}
			config, e := strconv.ParseUint(strings.TrimPrefix(strings.TrimSpace(string(b)), "config="), 0, 64)
			if e != nil {
				continue
			}
			attr := unix.PerfEventAttr{Type: uint32(typ), Config: config, Read_format: unix.PERF_FORMAT_TOTAL_TIME_ENABLED}
			attr.Size = uint32(unsafe.Sizeof(attr))
			fd, e := unix.PerfEventOpen(&attr, -1, cpuID, -1, unix.PERF_FLAG_FD_CLOEXEC)
			if e != nil {
				continue
			}
			c = &engineCounter{fd: fd}
			engines[p] = c
		}
		b := make([]byte, 16)
		n, e := unix.Read(c.fd, b)
		if e != nil || n != 16 {
			unix.Close(c.fd)
			delete(engines, p)
			continue
		}
		value, enabled := binary.NativeEndian.Uint64(b[:8]), binary.NativeEndian.Uint64(b[8:])
		if c.ready && enabled > c.enabled && value >= c.value {
			usage := math.Min(100, 100*float64(value-c.value)/float64(enabled-c.enabled))
			values[strings.TrimSuffix(filepath.Base(p), "-busy")] = usage
			if max == nil || usage > max.(float64) {
				max = usage
			}
		}
		c.value, c.enabled, c.ready = value, enabled, true
	}
	return max, values
}
func otherGPU() M {
	paths, e := filepath.Glob("/sys/bus/pci/devices/*")
	if e != nil {
		return M{"status": "unavailable", "reason": "GPU inventory unavailable"}
	}
	var found M
	for _, p := range paths {
		class, _ := os.ReadFile(p + "/class")
		if !strings.HasPrefix(strings.TrimSpace(string(class)), "0x03") {
			continue
		}
		vendor, _ := os.ReadFile(p + "/vendor")
		found = M{"status": "present", "name": "GPU", "reason": "Driver telemetry unavailable"}
		switch strings.TrimSpace(string(vendor)) {
		case "0x8086":
			usage, eng := intelUsage()
			cards, _ := filepath.Glob(p + "/drm/card[0-9]*")
			var clock any
			for _, card := range cards {
				if !strings.Contains(filepath.Base(card), "-") {
					clock = readNum(card+"/gt_cur_freq_mhz", 1)
					break
				}
			}
			return M{"status": "present", "name": env("INTEL_GPU_NAME", "Intel integrated GPU"), "kind": "integrated", "usage": usage, "engines": eng, "core_clock": clock, "memory_label": "Shared RAM"}
		case "0x10de":
			found["name"] = "NVIDIA GPU"
		case "0x1002":
			found["name"] = "AMD GPU"
		case "0x1af4", "0x1234", "0x1b36":
			found["name"] = "Virtual display adapter"
			found["reason"] = "No hardware GPU"
			found["status"] = "absent"
		}
	}
	if found != nil {
		return found
	}
	return M{"status": "absent", "name": "No GPU", "reason": "No GPU detected"}
}
