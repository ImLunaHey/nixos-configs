package main

import (
	"fmt"
	"github.com/shirou/gopsutil/v4/disk"
	"path/filepath"
	"regexp"
	"strconv"
	"time"
)

var portPattern = regexp.MustCompile(`-ata-([0-9]+)\.`)

func drivePort(path any) any {
	s, _ := path.(string)
	match := portPattern.FindStringSubmatch(s)
	if len(match) != 2 {
		return nil
	}
	n, _ := strconv.Atoi(match[1])
	return n
}

var previousDrives = map[string]disk.IOCountersStat{}
var previousDrivesAt time.Time

func addDriveStats(data M) {
	now := time.Now()
	elapsed := now.Sub(previousDrivesAt).Seconds()
	ios, err := disk.IOCounters()
	sensors := sensorLines()
	for _, d := range data["drives"].([]M) {
		path, _ := d["path"].(string)
		resolved, e := filepath.EvalSymlinks(path)
		if e != nil {
			continue
		}
		// Resolve the partition's parent, so counters include all activity on the drive.
		block, e := filepath.EvalSymlinks("/sys/class/block/" + filepath.Base(resolved))
		if e != nil {
			continue
		}
		device := filepath.Base(filepath.Dir(block))
		d["device"] = device
		if temp, ok := sensors["temp_"+device].(string); ok {
			d["temperature"] = num(temp)
		}
		current, ok := ios[device]
		if !ok || err != nil {
			continue
		}
		d["size"] = currentSize(device, d["size"])
		if prev, ok := previousDrives[device]; ok && !previousDrivesAt.IsZero() {
			d["read"] = rate(current.ReadBytes, prev.ReadBytes, elapsed)
			d["write"] = rate(current.WriteBytes, prev.WriteBytes, elapsed)
			d["iops"] = rate(current.ReadCount+current.WriteCount, prev.ReadCount+prev.WriteCount, elapsed)
			d["busy"] = min(100, rate(current.IoTime, prev.IoTime, elapsed)/10)
		}
	}
	if err == nil {
		previousDrives = ios
		previousDrivesAt = now
	}
}
func currentSize(device string, fallback any) any {
	if n := readNum(fmt.Sprintf("/sys/class/block/%s/size", device), 1.0/512); n != nil {
		return n
	}
	return fallback
}
