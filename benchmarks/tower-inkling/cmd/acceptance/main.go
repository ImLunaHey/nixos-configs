// Functional smoke tests for the OpenAI-compatible endpoint, with real tool results.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

func main() {
	client := &http.Client{Timeout: 2 * time.Minute}
	call := func(name string, messages []any, extra map[string]any) map[string]any {
		body := map[string]any{"model": "inkling-2-mini-abliterated", "messages": messages, "temperature": 0, "seed": 42, "max_tokens": 512, "reasoning_effort": "low"}
		for k, v := range extra {
			body[k] = v
		}
		b, _ := json.Marshal(body)
		start := time.Now()
		r, e := client.Post("http://127.0.0.1:8080/v1/chat/completions", "application/json", bytes.NewReader(b))
		if e != nil {
			panic(e)
		}
		raw, e := io.ReadAll(r.Body)
		r.Body.Close()
		if e != nil {
			panic(e)
		}
		if r.StatusCode != 200 {
			panic(string(raw))
		}
		var result map[string]any
		if e = json.Unmarshal(raw, &result); e != nil {
			panic(e)
		}
		choice := result["choices"].([]any)[0].(map[string]any)
		if choice["finish_reason"] == "length" {
			panic("truncated: " + name)
		}
		record := map[string]any{"case": name, "response": result, "wall_s": time.Since(start).Seconds()}
		json.NewEncoder(os.Stdout).Encode(record)
		return choice["message"].(map[string]any)
	}
	user := func(s string) any { return map[string]any{"role": "user", "content": s} }
	chat := call("chat", []any{user("Reply with exactly: Ready on Tower")}, nil)
	if strings.TrimSpace(fmt.Sprint(chat["content"])) != "Ready on Tower" {
		panic("chat mismatch")
	}
	math := call("reasoning", []any{user("What is 17 times 12? Answer briefly.")}, nil)
	if !strings.Contains(fmt.Sprint(math["content"]), "204") {
		panic("reasoning mismatch")
	}
	messages := []any{user("What is the current temperature in London? Use the temperature tool.")}
	fn := map[string]any{"name": "get_temperature", "description": "Get current temperature in Celsius", "parameters": map[string]any{"type": "object", "properties": map[string]any{"city": map[string]any{"type": "string"}}, "required": []string{"city"}}}
	tool := call("tool-call", messages, map[string]any{"tools": []any{map[string]any{"type": "function", "function": fn}}, "tool_choice": map[string]any{"type": "function", "function": map[string]any{"name": "get_temperature"}}})
	calls, ok := tool["tool_calls"].([]any)
	if !ok || len(calls) != 1 {
		panic("missing tool call")
	}
	tc := calls[0].(map[string]any)
	f := tc["function"].(map[string]any)
	if f["name"] != "get_temperature" {
		panic("wrong tool")
	}
	var args map[string]any
	if e := json.Unmarshal([]byte(f["arguments"].(string)), &args); e != nil {
		panic(e)
	}
	if !strings.EqualFold(fmt.Sprint(args["city"]), "London") {
		panic("wrong arguments")
	}
	messages = append(messages, tool, map[string]any{"role": "tool", "tool_call_id": tc["id"], "content": "{\"temperature_celsius\":17,\"city\":\"London\"}"})
	answer := call("tool-result", messages, nil)
	if !strings.Contains(fmt.Sprint(answer["content"]), "17") {
		panic("tool result missing")
	}
	fmt.Fprintln(os.Stderr, "All chat, reasoning and tool round-trip checks passed.")
}
