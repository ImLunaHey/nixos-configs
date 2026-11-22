package main

import (
	"bytes"
	"encoding/xml"
	"regexp"
	"strings"

	"github.com/shirou/gopsutil/v4/disk"
)

// APFS volumes/snapshots are virtual devices; IORegistry reports activity on
// their backing physical disks. Resolve the Data volume instead of guessing
// disk0 or summing unrelated external disks and disk images.
func apfsPhysicalDisks(b []byte) []string {
	d := xml.NewDecoder(bytes.NewReader(b))
	var devices []string
	seen := map[string]bool{}
	physical := regexp.MustCompile(`^(disk[0-9]+)s[0-9]+$`)
	key := ""
	for {
		t, err := d.Token()
		if err != nil {
			break
		}
		e, ok := t.(xml.StartElement)
		if !ok {
			continue
		}
		if e.Name.Local == "key" {
			if d.DecodeElement(&key, &e) != nil {
				return nil
			}
		} else if e.Name.Local == "string" {
			var value string
			if d.DecodeElement(&value, &e) != nil {
				return nil
			}
			if key == "APFSPhysicalStore" {
				match := physical.FindStringSubmatch(value)
				if len(match) == 2 && !seen[match[1]] {
					devices = append(devices, match[1])
					seen[match[1]] = true
				}
			}
			key = ""
		}
	}
	return devices
}

func diskCounters(all map[string]disk.IOCountersStat, devices string) (disk.IOCountersStat, bool) {
	var total disk.IOCountersStat
	for _, name := range strings.Split(devices, ",") {
		c, ok := all[name]
		if !ok {
			return disk.IOCountersStat{}, false
		}
		total.ReadBytes += c.ReadBytes
		total.WriteBytes += c.WriteBytes
		total.ReadCount += c.ReadCount
		total.WriteCount += c.WriteCount
	}
	return total, true
}
