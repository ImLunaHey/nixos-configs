package main

import (
	"github.com/shirou/gopsutil/v4/disk"
	"reflect"
	"testing"
)

func TestAPFSPhysicalStores(t *testing.T) {
	b := []byte(`<plist><dict><key>DeviceIdentifier</key><string>disk3s5</string><key>ParentWholeDisk</key><string>disk3</string><key>APFSPhysicalStores</key><array><dict><key>APFSPhysicalStore</key><string>disk0s2</string></dict><dict><key>APFSPhysicalStore</key><string>disk2s1</string></dict><dict><key>APFSPhysicalStore</key><string>disk0s3</string></dict></array></dict></plist>`)
	if got := apfsPhysicalDisks(b); !reflect.DeepEqual(got, []string{"disk0", "disk2"}) {
		t.Fatal(got)
	}
	if got := apfsPhysicalDisks([]byte(`<plist><dict><key>DeviceIdentifier</key><string>disk3s5</string></dict></plist>`)); len(got) != 0 {
		t.Fatal("guessed physical disk", got)
	}
}
func TestDiskCountersMissingAndMultipleStores(t *testing.T) {
	all := map[string]disk.IOCountersStat{"disk0": {ReadBytes: 100, WriteBytes: 200}, "disk2": {ReadBytes: 300, WriteBytes: 400}, "external": {ReadBytes: 999}}
	if c, ok := diskCounters(all, "disk0,disk2"); !ok || c.ReadBytes != 400 || c.WriteBytes != 600 {
		t.Fatal(c, ok)
	}
	if _, ok := diskCounters(all, "disk3s5"); ok {
		t.Fatal("missing device reported as idle")
	}
	if _, ok := diskCounters(all, "disk0,missing"); ok {
		t.Fatal("partial totals accepted")
	}
}
