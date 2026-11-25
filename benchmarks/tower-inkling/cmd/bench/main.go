// Run against llama.cpp's native completion endpoint; token counts and timings
// come from the server, not SSE chunk counts. No model or sampler changes.
package main

import (
	"bufio"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

var base = flag.String("url", "http://127.0.0.1:8080", "server")
var tag = flag.String("tag", "baseline", "experiment label")
var mode = flag.String("mode", "panel", "panel or needle")
var size = flag.Int("size", 4096, "prefill or needle token count")
var samples = flag.Int("samples", 6, "samples")
var capMiB = flag.Int("cap-mib", 14750, "GPU memory cap")
var fixturePath = flag.String("fixtures", "", "replay exact tokenized requests from JSON")
var writeFixtures = flag.String("write-fixtures", "", "write tokenized requests without benchmarking")
var client = &http.Client{Timeout: 15 * time.Minute}

type fixture struct {
	Label    string   `json:"label"`
	Prompt   []any    `json:"prompt"`
	Predict  int      `json:"predict"`
	Expected []string `json:"expected,omitempty"`
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}
func post(path string, body any) map[string]any {
	b, _ := json.Marshal(body)
	r, e := client.Post(*base+path, "application/json", bytes.NewReader(b))
	must(e)
	defer r.Body.Close()
	if r.StatusCode != 200 {
		d, _ := io.ReadAll(r.Body)
		panic(string(d))
	}
	var out map[string]any
	must(json.NewDecoder(r.Body).Decode(&out))
	return out
}
func tokens(s string) []any {
	return post("/tokenize", map[string]any{"content": s, "add_special": false, "parse_special": true})["tokens"].([]any)
}
func chat(s string) string {
	return "<|message_system|><|content_text|>Thinking effort level: 0<|end_message|><|message_user|><|content_text|>" + s + "<|end_message|><|message_model|><|content_text|>"
}
func prompt(n int, needle bool) ([]any, []string) {
	prefix := tokens("<|message_system|><|content_text|>Thinking effort level: 0<|end_message|><|message_user|><|content_text|>Read this reference document.\n")
	suffix := tokens("\nSummarize the reference document and explain its design tradeoffs in detail.<|end_message|><|message_model|><|content_text|>")
	codes := []string{"ALPHA=J7Q9V2", "BETA=R4M8K6", "GAMMA=T3X5N1"}
	if needle {
		suffix = tokens("\nReturn only the exact ALPHA, BETA and GAMMA secret codes from the document, one per line in NAME=CODE form. No commentary.<|end_message|><|message_model|><|content_text|>")
	}
	var text strings.Builder
	for i := 0; i < 6000; i++ {
		fmt.Fprintf(&text, "Record %d: service node-%d stores shard-%d; cache expiry is %d seconds; replication uses %d peers.\n", i, i%97, i%43, 30+i%71, 2+i%3)
	}
	fill := tokens(text.String())
	room := n - len(prefix) - len(suffix)
	body := append([]any{}, fill[:room]...)
	if needle {
		for i, code := range codes {
			ts := tokens("\nSecret code: " + code + "\n")
			at := room * (i*4 + 1) / 10
			copy(body[at:at+len(ts)], ts)
		}
	}
	out := append(prefix, body...)
	out = append(out, suffix...)
	return out, codes
}
func run(label string, p any, n int, expected []string) {
	// Pass exact token IDs to make cold-prefill accounting comparable across engines.
	if s, ok := p.(string); ok {
		p = tokens(s)
	}
	inputTokens := len(p.([]any))
	processes, err := exec.Command("nvidia-smi", "--query-compute-apps=process_name", "--format=csv,noheader").Output()
	must(err)
	processList := strings.Split(strings.TrimSpace(string(processes)), "\n")
	if len(processList) != 1 || !strings.HasSuffix(processList[0], "/llama-server") {
		panic("another GPU compute process is present")
	}
	powerBefore, err := exec.Command("nvidia-smi", "--query-gpu=power.limit", "--format=csv,noheader,nounits").Output()
	must(err)
	slots, e := client.Get(*base + "/slots")
	must(e)
	var ss []struct {
		Busy bool `json:"is_processing"`
	}
	must(json.NewDecoder(slots.Body).Decode(&ss))
	slots.Body.Close()
	for _, s := range ss {
		if s.Busy {
			panic("server busy; refusing concurrent benchmark")
		}
	}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	var mu sync.Mutex
	peak := 0
	var violation string
	sample := func() {
		out, e := exec.Command("nvidia-smi", "--query-gpu=memory.used", "--format=csv,noheader,nounits").Output()
		if e != nil {
			mu.Lock()
			violation = "GPU sampler failed"
			mu.Unlock()
			cancel()
			return
		}
		used, e := strconv.Atoi(strings.TrimSpace(string(out)))
		if e != nil {
			cancel()
			return
		}
		mu.Lock()
		if used > peak {
			peak = used
		}
		if used > *capMiB {
			violation = "GPU memory cap exceeded"
			cancel()
		}
		mu.Unlock()
	}
	sample()
	done := make(chan struct{})
	go func() {
		defer close(done)
		tick := time.NewTicker(time.Second)
		defer tick.Stop()
		for {
			select {
			case <-ctx.Done():
				return
			case <-tick.C:
				sample()
			}
		}
	}()
	body, _ := json.Marshal(map[string]any{"prompt": p, "n_predict": n, "temperature": 0, "seed": 42, "cache_prompt": false, "stream": true, "return_tokens": true})
	req, e := http.NewRequestWithContext(ctx, "POST", *base+"/completion", bytes.NewReader(body))
	must(e)
	req.Header.Set("Content-Type", "application/json")
	start := time.Now()
	resp, e := client.Do(req)
	if e != nil {
		cancel()
		<-done
		mu.Lock()
		failure := map[string]any{"at": time.Now().UTC(), "tag": *tag, "case": label, "error": e.Error(), "violation": violation, "peak_vram_mib": peak}
		mu.Unlock()
		must(json.NewEncoder(os.Stdout).Encode(failure))
	}
	must(e)
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		panic(fmt.Sprint("HTTP ", resp.StatusCode))
	}
	scan := bufio.NewScanner(resp.Body)
	scan.Buffer(make([]byte, 4096), 4<<20)
	var content strings.Builder
	ttft := 0.0
	var final map[string]any
	for scan.Scan() {
		line := scan.Text()
		if !strings.HasPrefix(line, "data: ") {
			continue
		}
		var chunk map[string]any
		if json.Unmarshal([]byte(strings.TrimPrefix(line, "data: ")), &chunk) != nil {
			continue
		}
		if s, ok := chunk["content"].(string); ok && s != "" {
			if ttft == 0 {
				ttft = float64(time.Since(start).Microseconds()) / 1000
			}
			content.WriteString(s)
		}
		if chunk["stop"] == true {
			final = chunk
		}
	}
	scanErr := scan.Err()
	wall := time.Since(start).Seconds()
	cancel()
	<-done
	if scanErr != nil {
		must(json.NewEncoder(os.Stdout).Encode(map[string]any{"at": time.Now().UTC(), "tag": *tag, "case": label, "error": scanErr.Error(), "violation": violation, "peak_vram_mib": peak, "wall_s": wall}))
		panic(scanErr)
	}
	powerAfter, err := exec.Command("nvidia-smi", "--query-gpu=power.limit", "--format=csv,noheader,nounits").Output()
	must(err)
	if string(powerBefore) != string(powerAfter) {
		panic("GPU power configuration changed during run")
	}
	if violation != "" {
		panic(violation)
	}
	if final == nil {
		panic("missing final response")
	}
	timings := final["timings"].(map[string]any)
	if cached, present := timings["cache_n"]; present && cached != float64(0) {
		panic("unexpected cached prompt")
	}
	if timings["prompt_n"] != float64(inputTokens) {
		panic(fmt.Sprintf("prompt processing mismatch: expected %d, got %v", inputTokens, timings["prompt_n"]))
	}
	ok := true
	for _, code := range expected {
		ok = ok && strings.Contains(content.String(), code)
	}
	record := map[string]any{"at": time.Now().UTC(), "tag": *tag, "case": label, "ttft_ms": ttft, "wall_s": wall, "timings": timings, "peak_vram_mib": peak, "output": content.String(), "output_sha256": fmt.Sprintf("%x", sha256.Sum256([]byte(content.String()))), "needle_pass": ok, "truncated": final["truncated"]}
	// Both engines start the decode clock after the first token. Older ik servers
	// divide by all predicted tokens; normalize that off-by-one without hiding raw data.
	record["decode_tps_normalized"] = (timings["predicted_n"].(float64) - 1) * 1000 / timings["predicted_ms"].(float64)
	record["input_tokens"] = inputTokens
	inputJSON, err := json.Marshal(p)
	must(err)
	record["input_sha256"] = fmt.Sprintf("%x", sha256.Sum256(inputJSON))
	must(json.NewEncoder(os.Stdout).Encode(record))
	if !ok || final["truncated"] == true {
		panic("quality gate failed")
	}
}
func main() {
	flag.Parse()
	lock, e := os.OpenFile("/tmp/inkling-benchmark.lock", os.O_CREATE|os.O_RDWR, 0600)
	must(e)
	defer lock.Close()
	must(syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB))
	defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
	if *fixturePath != "" {
		data, err := os.ReadFile(*fixturePath)
		must(err)
		var cases []fixture
		must(json.Unmarshal(data, &cases))
		for _, c := range cases {
			run(c.Label, c.Prompt, c.Predict, c.Expected)
		}
		return
	}
	var cases []fixture
	if *mode == "needle" {
		p, c := prompt(*size, true)
		cases = append(cases, fixture{"needle", p, 128, c})
	} else {
		cases = append(cases, fixture{"warmup", tokens(chat("Explain why indexes speed up database queries.")), 64, nil})
		panel := []string{"Explain why indexes speed up database queries and when they hurt performance.", "Write a Go function that merges two sorted integer slices. Explain edge cases.", "Explain how a transformer KV cache speeds up autoregressive generation.", "Compare optimistic and pessimistic database locking with practical examples.", "Write a Rust function to find the first unique character in a string and explain it.", "Explain how TCP congestion control responds to packet loss and latency."}
		for i := 0; i < *samples; i++ {
			cases = append(cases, fixture{fmt.Sprintf("decode-%d", i), tokens(chat(panel[i%len(panel)])), 192, nil})
		}
		p, _ := prompt(*size, false)
		for i := 0; i < 3; i++ {
			cases = append(cases, fixture{fmt.Sprintf("prefill-%d-%d", *size, i), p, 64, nil})
		}
	}
	if *writeFixtures != "" {
		data, err := json.Marshal(cases)
		must(err)
		must(os.WriteFile(*writeFixtures, append(data, '\n'), 0644))
		return
	}
	for _, c := range cases {
		run(c.Label, c.Prompt, c.Predict, c.Expected)
	}
}
