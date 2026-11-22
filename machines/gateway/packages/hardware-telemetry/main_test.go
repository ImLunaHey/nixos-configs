package main

import (
	"testing"
)

func TestZFSReplacement(t *testing.T) {
	data, e := parseZFS([]byte(`{"pools":{"storage":{"state":"DEGRADED","error_count":0,"scan_stats":{"function":"RESILVER","state":"SCANNING","issued":95,"to_examine":100},"vdevs":{"storage":{"vdev_type":"root","total_space":1000,"alloc_space":930,"vdevs":{"replacing":{"vdev_type":"replacing","vdevs":{"old":{"vdev_type":"disk","name":"old","state":"CANT_OPEN","not_present":1},"new":{"vdev_type":"disk","name":"new","state":"ONLINE","scan_processed":50}}}}}}}}}`), "storage")
	if e != nil {
		t.Fatal(e)
	}
	if data["scan_percent"] != float64(95) {
		t.Fatal(data)
	}
	drives := data["drives"].([]M)
	if len(drives) != 2 {
		t.Fatal(drives)
	}
	for _, d := range drives {
		if d["replacing"] != true {
			t.Fatal(d)
		}
	}
}
func TestUnavailableIsNotHealthy(t *testing.T) {
	for _, input := range []string{`{}`, `{"pools":{"storage":{}}}`, `bad`} {
		if _, e := parseZFS([]byte(input), "storage"); e == nil {
			t.Fatal("accepted incomplete status")
		}
	}
}
func TestCounterReset(t *testing.T) {
	if rate(1, 100, 2) != 0 {
		t.Fatal("counter reset caused spike")
	}
	if rate(500, 100, 2) != 200 {
		t.Fatal("bad rate")
	}
}
