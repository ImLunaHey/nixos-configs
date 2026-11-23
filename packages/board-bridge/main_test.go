package main

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func reply() event {
	var e event
	_ = json.Unmarshal([]byte(`{"cursor":"2","type":"message.posted","message":{"id":"reply","re":"root","channel":"nixos-configs"},"actor":{"kind":"person"},"payload":{"by":{"profile":null}}}`), &e)
	return e
}

func TestCandidate(t *testing.T) {
	cases := []struct {
		name string
		edit func(*event)
		want bool
	}{
		{"human reply", func(*event) {}, true},
		{"agent reply", func(e *event) { e.Actor.Kind = "agent" }, false},
		{"profile even if actor says person", func(e *event) { p := "codex"; e.Payload.By.Profile = &p }, false},
		{"root", func(e *event) { e.Message.Re = nil }, false},
		{"reaction", func(e *event) { e.Type = "reaction.added" }, false},
		{"another channel", func(e *event) { e.Message.Channel = "fleet-monitor" }, false},
		{"no message", func(e *event) { e.Message = nil }, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			e := reply()
			tc.edit(&e)
			if candidate(e, "nixos-configs") != tc.want {
				t.Fatal("unexpected routing")
			}
		})
	}
}

func fixture(t *testing.T, handler http.HandlerFunc) *bridge {
	t.Helper()
	server := httptest.NewServer(handler)
	t.Cleanup(server.Close)
	dir := t.TempDir()
	token := filepath.Join(dir, "token.json")
	if err := os.WriteFile(token, []byte(`{"token":"test-token"}`), 0600); err != nil {
		t.Fatal(err)
	}
	return &bridge{boardURL: server.URL, tokenFile: token, stateDir: dir, client: &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}}
}

func TestRetryAndRestart(t *testing.T) {
	failures := true
	deliveries := 0
	var payload map[string]string
	hook := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		deliveries++
		_ = json.NewDecoder(r.Body).Decode(&payload)
		if failures {
			w.WriteHeader(503)
		} else {
			w.WriteHeader(202)
		}
	}))
	defer hook.Close()
	b := fixture(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer test-token" {
			t.Error("missing Board auth")
		}
		switch r.URL.Path {
		case "/events":
			q := r.URL.Query()
			if q.Get("after") == "" {
				_, _ = w.Write([]byte(`{"events":[],"cursor":"1"}`))
				return
			}
			if q.Get("label") != "wake=nixos-configs" || q.Get("channel") != "nixos-configs" {
				t.Error("missing route filters")
			}
			if q.Get("after") == "1" {
				_ = json.NewEncoder(w).Encode(page{Events: []event{reply()}, Cursor: "2"})
			} else {
				_, _ = w.Write([]byte(`{"events":[],"cursor":"3"}`))
			}
		case "/messages/root":
			_, _ = w.Write([]byte(`{"message":{"id":"root","channel":"nixos-configs","labels":{"wake":"nixos-configs"}}}`))
		default:
			t.Error("unexpected path")
			w.WriteHeader(404)
		}
	})
	ctx := context.Background()
	r := route{Channel: "nixos-configs", WebhookURL: hook.URL}
	name := "nixos-configs"
	if err := b.step(ctx, name, r); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(b.stateDir, name+".cursor")
	assertCursor := func(want string) {
		t.Helper()
		data, _ := os.ReadFile(path)
		if strings.TrimSpace(string(data)) != want {
			t.Fatalf("cursor = %q, want %q", data, want)
		}
	}
	assertCursor("1")
	if err := b.step(ctx, name, r); err == nil {
		t.Fatal("failed webhook accepted")
	}
	assertCursor("1")
	// A new bridge process resumes from the same disk cursor.
	restarted := *b
	failures = false
	if err := restarted.step(ctx, name, r); err != nil {
		t.Fatal(err)
	}
	assertCursor("2")
	if deliveries != 2 || payload["eventId"] != "nixos-configs:2" || payload["threadId"] != "root" {
		t.Fatalf("wrong retry identity: %v, %d", payload, deliveries)
	}
	if err := restarted.step(ctx, name, r); err != nil {
		t.Fatal(err)
	}
	assertCursor("3")
	if deliveries != 2 {
		t.Fatal("already acknowledged event delivered again")
	}
}

func TestCancelledWake(t *testing.T) {
	called := false
	hook := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { called = true }))
	defer hook.Close()
	b := fixture(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"message":{"channel":"nixos-configs","labels":{}}}`))
	})
	if err := b.deliver(context.Background(), "nixos-configs", route{Channel: "nixos-configs", WebhookURL: hook.URL}, reply()); err != nil {
		t.Fatal(err)
	}
	if called {
		t.Fatal("removed wake label still delivered")
	}
}

func TestTokenRotation(t *testing.T) {
	want := "test-token"
	b := fixture(t, func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer "+want {
			t.Error("stale token")
		}
		_, _ = w.Write([]byte(`{}`))
	})
	var result map[string]any
	if err := b.get(context.Background(), "/events", &result); err != nil {
		t.Fatal(err)
	}
	want = "rotated"
	_ = os.WriteFile(b.tokenFile, []byte(`{"token":"rotated"}`), 0600)
	if err := b.get(context.Background(), "/events", &result); err != nil {
		t.Fatal(err)
	}
}

func TestRouteValidation(t *testing.T) {
	for _, data := range []string{`{}`, `{"../bad":{"channel":"x","webhookUrl":"https://example.test"}}`, `{"ok":{"channel":"x","webhookUrl":"http://example.test"}}`, `{"ok":{"channel":"x","webhookUrl":"https://user:secret@example.test"}}`} {
		path := filepath.Join(t.TempDir(), "routes.json")
		_ = os.WriteFile(path, []byte(data), 0600)
		if _, err := readRoutes(path); err == nil {
			t.Fatalf("accepted invalid routes: %s", data)
		}
	}
}

func TestRedirectDoesNotLeakBearerURL(t *testing.T) {
	leaked := false
	target := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { leaked = true }))
	defer target.Close()
	hook := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, target.URL, 307) }))
	defer hook.Close()
	b := fixture(t, func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"message":{"channel":"nixos-configs","labels":{"wake":"nixos-configs"}}}`))
	})
	err := b.deliver(context.Background(), "nixos-configs", route{Channel: "nixos-configs", WebhookURL: hook.URL + "/secret"}, reply())
	if err == nil || strings.Contains(err.Error(), hook.URL) || strings.Contains(err.Error(), "secret") || leaked {
		t.Fatalf("unsafe redirect/error: %v", err)
	}
}
