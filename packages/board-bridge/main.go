// Board's event log is durable; its local watcher timers are not. Poll with a
// persisted cursor and advance only after T3 accepts the delivery. T3's replay
// key makes a retry after an ambiguous response or process crash harmless.
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"sync"
	"syscall"
	"time"
)

type route struct {
	Channel    string `json:"channel"`
	WebhookURL string `json:"webhookUrl"`
}
type message struct {
	ID      string            `json:"id"`
	Re      *string           `json:"re"`
	Channel string            `json:"channel"`
	Labels  map[string]string `json:"labels"`
}
type event struct {
	Cursor  string   `json:"cursor"`
	Type    string   `json:"type"`
	Message *message `json:"message"`
	Payload struct {
		By struct {
			Profile *string `json:"profile"`
		} `json:"by"`
	} `json:"payload"`
	Actor struct {
		Kind string `json:"kind"`
	} `json:"actor"`
}
type page struct {
	Events []event `json:"events"`
	Cursor string  `json:"cursor"`
}
type bridge struct {
	boardURL, tokenFile, stateDir string
	client                        *http.Client
}

var routeName = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]{0,63}$`)

func readRoutes(path string) (map[string]route, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var routes map[string]route
	if err := json.Unmarshal(data, &routes); err != nil {
		return nil, errors.New("invalid routes JSON")
	}
	if len(routes) == 0 {
		return nil, errors.New("no routes configured")
	}
	for name, r := range routes {
		u, err := url.Parse(r.WebhookURL)
		if !routeName.MatchString(name) || r.Channel == "" || err != nil || u.Scheme != "https" || u.Host == "" || u.User != nil || u.Fragment != "" {
			return nil, errors.New("invalid route: require a safe name, channel and HTTPS webhook URL")
		}
	}
	return routes, nil
}

func (b *bridge) get(ctx context.Context, path string, result any) error {
	// Re-read the token because vb serve rotates it whenever the server restarts.
	data, err := os.ReadFile(b.tokenFile)
	if err != nil {
		return errors.New("Board token unavailable")
	}
	var auth struct {
		Token string `json:"token"`
	}
	if json.Unmarshal(data, &auth) != nil || auth.Token == "" {
		return errors.New("invalid Board token")
	}
	req, err := http.NewRequestWithContext(ctx, "GET", b.boardURL+path, nil)
	if err != nil {
		return errors.New("invalid Board request")
	}
	req.Header.Set("Authorization", "Bearer "+auth.Token)
	req.Header.Set("Accept", "application/json")
	resp, err := b.client.Do(req)
	if err != nil {
		return errors.New("Board request failed")
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("Board HTTP %d", resp.StatusCode)
	}
	return json.NewDecoder(io.LimitReader(resp.Body, 8<<20)).Decode(result)
}

func candidate(e event, channel string) bool {
	// Only people's replies wake a thread. Agent profiles cannot wake themselves
	// (or each other); edits, labels, roots and reactions never start turns.
	return e.Type == "message.posted" && e.Message != nil && e.Message.Re != nil &&
		*e.Message.Re != "" && e.Message.Channel == channel && e.Actor.Kind == "person" &&
		(e.Payload.By.Profile == nil || *e.Payload.By.Profile == "")
}

func (b *bridge) deliver(ctx context.Context, name string, r route, e event) error {
	if !candidate(e, r.Channel) {
		return nil
	}
	var thread struct {
		Message message `json:"message"`
	}
	if err := b.get(ctx, "/messages/"+url.PathEscape(*e.Message.Re), &thread); err != nil {
		return err
	}
	// Recheck the current root: removing wake cancels queued wake-ups too.
	if thread.Message.Labels["wake"] != name || thread.Message.Channel != r.Channel {
		return nil
	}
	payload, _ := json.Marshal(map[string]string{
		"source": "lake-board", "route": name, "eventId": name + ":" + e.Cursor,
		"threadId": *e.Message.Re, "messageId": e.Message.ID,
	})
	deliveryCtx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(deliveryCtx, "POST", r.WebhookURL, bytes.NewReader(payload))
	if err != nil {
		return errors.New("invalid webhook request")
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := b.client.Do(req)
	// Never log transport errors: they can contain the secret bearer URL.
	if err != nil {
		return errors.New("webhook delivery failed; will retry")
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("webhook HTTP %d; will retry", resp.StatusCode)
	}
	log.Printf("route %s: delivered event %s", name, e.Cursor)
	return nil
}

func saveCursor(path, cursor string) error {
	if cursor == "" {
		return errors.New("Board returned an empty cursor")
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".cursor-*")
	if err != nil {
		return err
	}
	tmp := file.Name()
	defer os.Remove(tmp)
	if _, err = file.WriteString(cursor + "\n"); err == nil {
		err = file.Sync()
	}
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if err = os.Rename(tmp, path); err != nil {
		return err
	}
	dir, err := os.Open(filepath.Dir(path))
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func (b *bridge) step(ctx context.Context, name string, r route) error {
	path := filepath.Join(b.stateDir, name+".cursor")
	raw, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		// First enrollment starts now. Persist the head before waiting so a crash
		// after enrollment cannot silently skip replies received while down.
		var head page
		if err := b.get(ctx, "/events?wait=0", &head); err != nil {
			return err
		}
		return saveCursor(path, head.Cursor)
	}
	if err != nil {
		return err
	}
	cursor := strings.TrimSpace(string(raw))
	if cursor == "" {
		return errors.New("empty saved cursor; refusing to skip events")
	}
	query := url.Values{"channel": {r.Channel}, "label": {"wake=" + name}, "after": {cursor}, "wait": {"30"}}
	var p page
	if err := b.get(ctx, "/events?"+query.Encode(), &p); err != nil {
		return err
	}
	for _, e := range p.Events {
		if err := b.deliver(ctx, name, r, e); err != nil {
			return err
		}
		if err := saveCursor(path, e.Cursor); err != nil {
			return err
		}
	}
	if p.Cursor != cursor {
		return saveCursor(path, p.Cursor)
	}
	return nil
}

func main() {
	log.SetFlags(log.LstdFlags | log.LUTC)
	routes, err := readRoutes(os.Getenv("BOARD_ROUTES_FILE"))
	if err != nil {
		log.Fatal(err)
	}
	boardURL := strings.TrimRight(os.Getenv("BOARD_URL"), "/")
	u, err := url.Parse(boardURL)
	if err != nil || u.Scheme != "http" || u.Hostname() != "127.0.0.1" {
		log.Fatal("BOARD_URL must use local loopback HTTP")
	}
	stateDir := os.Getenv("STATE_DIRECTORY")
	if stateDir == "" {
		log.Fatal("STATE_DIRECTORY required")
	}
	if err := os.MkdirAll(stateDir, 0700); err != nil {
		log.Fatal(err)
	}
	sum := sha256.Sum256([]byte(boardURL))
	tokenFile := filepath.Join(os.Getenv("XDG_CONFIG_HOME"), "board", "local", hex.EncodeToString(sum[:])[:32]+".json")
	b := &bridge{boardURL: boardURL, tokenFile: tokenFile, stateDir: stateDir, client: &http.Client{
		Timeout:       45 * time.Second,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer cancel()
	var wg sync.WaitGroup
	for name, r := range routes {
		wg.Add(1)
		go func() {
			defer wg.Done()
			delay := time.Second
			for ctx.Err() == nil {
				if err := b.step(ctx, name, r); err != nil {
					if ctx.Err() != nil {
						return
					}
					log.Printf("route %s: %v", name, err)
					select {
					case <-ctx.Done():
						return
					case <-time.After(delay):
					}
					delay = min(delay*2, 30*time.Second)
				} else {
					delay = time.Second
				}
			}
		}()
	}
	wg.Wait()
}
