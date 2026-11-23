package main

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

var f *os.File

func read(v any) {
	if e := binary.Read(f, binary.LittleEndian, v); e != nil {
		panic(e)
	}
}
func str() string {
	var n uint64
	read(&n)
	b := make([]byte, n)
	_, e := io.ReadFull(f, b)
	if e != nil {
		panic(e)
	}
	return string(b)
}
func val(t uint32) any {
	switch t {
	case 0:
		var v uint8
		read(&v)
		return v
	case 1:
		var v int8
		read(&v)
		return v
	case 2:
		var v uint16
		read(&v)
		return v
	case 3:
		var v int16
		read(&v)
		return v
	case 4:
		var v uint32
		read(&v)
		return v
	case 5:
		var v int32
		read(&v)
		return v
	case 6:
		var v float32
		read(&v)
		return v
	case 7:
		var v uint8
		read(&v)
		return v != 0
	case 8:
		return str()
	case 9:
		var k uint32
		var n uint64
		read(&k)
		read(&n)
		var vs []any
		for i := uint64(0); i < n; i++ {
			v := val(k)
			if n < 128 {
				vs = append(vs, v)
			}
		}
		if n >= 128 {
			return fmt.Sprintf("array[%d]", n)
		}
		return vs
	case 10:
		var v uint64
		read(&v)
		return v
	case 11:
		var v int64
		read(&v)
		return v
	case 12:
		var v float64
		read(&v)
		return v
	}
	panic(t)
}
func main() {
	if len(os.Args) != 2 {
		panic("usage: inkling-gguf MODEL.gguf")
	}
	var err error
	f, err = os.Open(os.Args[1])
	if err != nil {
		panic(err)
	}
	defer f.Close()
	var magic, version uint32
	var tensors, count uint64
	read(&magic)
	read(&version)
	if magic != 0x46554747 || version != 3 {
		panic("expected GGUF version 3")
	}
	read(&tensors)
	read(&count)
	m := map[string]any{}
	for i := uint64(0); i < count; i++ {
		k := str()
		var t uint32
		read(&t)
		v := val(t)
		if !strings.HasPrefix(k, "tokenizer.") {
			m[k] = v
		}
	}
	type tensor struct {
		Name                  string
		Offset, Params, Bytes uint64
		Mult                  float64
	}
	var ts []tensor
	re := regexp.MustCompile("^blk\\.([0-9]+)\\.")
	for i := uint64(0); i < tensors; i++ {
		name := str()
		var nd, typ uint32
		read(&nd)
		params := uint64(1)
		for j := uint32(0); j < nd; j++ {
			var d uint64
			read(&d)
			params *= d
		}
		read(&typ)
		var off uint64
		read(&off)
		mult := 1.0
		if match := re.FindStringSubmatch(name); len(match) > 0 {
			n, _ := strconv.Atoi(match[1])
			if n >= 6 && n < 18 {
				mult = 3
			}
		}
		ts = append(ts, tensor{Name: name, Offset: off, Params: params, Mult: mult})
	}
	pos, _ := f.Seek(0, io.SeekCurrent)
	dataStart := (pos + 31) / 32 * 32
	info, _ := f.Stat()
	sort.Slice(ts, func(i, j int) bool { return ts[i].Offset < ts[j].Offset })
	activeBytes := 0.0
	activeParams := 0.0
	for i := range ts {
		end := uint64(info.Size() - dataStart)
		if i+1 < len(ts) {
			end = ts[i+1].Offset
		}
		ts[i].Bytes = end - ts[i].Offset
		mult := ts[i].Mult
		if strings.Contains(ts[i].Name, "_exps.") {
			mult *= 8.0 / 128
		}
		if ts[i].Name == "token_embd.weight" {
			continue
		}
		activeBytes += float64(ts[i].Bytes) * mult
		if strings.HasSuffix(ts[i].Name, ".weight") {
			activeParams += float64(ts[i].Params) * mult
		}
	}
	m["measured_active_weight_bytes_per_decode"] = activeBytes
	m["estimated_active_linear_parameters"] = activeParams
	m["tensors"] = ts
	json.NewEncoder(os.Stdout).Encode(m)
}
