package main

import (
	"github.com/shirou/gopsutil/v4/mem"
	"regexp"
)

// IORegistry publishes AGX utilization to ordinary logged-in users; no sudo,
// powermetrics process, or private framework is needed.
func parseAppleGPU(b []byte) M {
	model := regexp.MustCompile(`"model"\s*=\s*"([^"]+)"`).FindSubmatch(b)
	if len(model) != 2 {
		return M{"status": "unavailable", "name": "Apple GPU", "reason": "GPU inventory unavailable"}
	}
	m := M{"name": string(model[1]) + " GPU", "kind": "integrated", "status": "present", "memory_label": "Shared RAM"}
	stats := regexp.MustCompile(`"PerformanceStatistics"\s*=\s*\{([^\n]+)\}`).FindSubmatch(b)
	if len(stats) == 2 {
		for key, field := range map[string]string{"Device Utilization %": "usage", "In use system memory": "memory_used"} {
			match := regexp.MustCompile(`"` + regexp.QuoteMeta(key) + `"\s*=\s*([0-9.]+)`).FindSubmatch(stats[1])
			if len(match) == 2 {
				m[field] = num(string(match[1]))
			}
		}
		if n, ok := m["memory_used"].(float64); ok {
			m["memory_used"] = n / 1048576
		}
	}
	return m
}
func appleGPU() M {
	b, e := command("/usr/sbin/ioreg", "-r", "-d", "1", "-c", "AGXAccelerator", "-l")
	if e != nil {
		return M{"status": "unavailable", "name": "Apple GPU", "reason": "IORegistry read failed"}
	}
	m := parseAppleGPU(b)
	// Apple GPUs share system RAM. This is system capacity, not dedicated VRAM.
	if memory, e := mem.VirtualMemory(); e == nil {
		m["memory_total"] = float64(memory.Total) / 1048576
	}
	return m
}
