package engine

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

// RunMeta captures correlation metadata for a single platctl run.
type RunMeta struct {
	Operation string   `json:"operation"`
	StartedAt string   `json:"started_at"`
	EnvFilter *string  `json:"env_filter"`
	Resume    bool     `json:"resume"`
	GitSHA    string   `json:"git_sha,omitempty"`
	Units     []string `json:"units"`
}

// Logger manages per-unit log files organized by run.
type Logger struct {
	mu      sync.Mutex
	dir     string // e.g., .platctl-logs/2026-05-26T143000_bootstrap
	waveNum int
	waveSet map[string]int // unit name → wave number
}

// NewLogger creates a log directory for this run and writes run.json.
func NewLogger(baseDir, operation string, envFilter *string, resume bool, units []string) (*Logger, error) {
	ts := time.Now().Format("2006-01-02T150405")
	suffix := operation
	if resume {
		suffix += "_resume"
	}
	dirName := fmt.Sprintf("%s_%s", ts, suffix)
	dir := filepath.Join(baseDir, dirName)

	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("creating log directory %s: %w", dir, err)
	}

	meta := RunMeta{
		Operation: operation,
		StartedAt: time.Now().Format(time.RFC3339),
		EnvFilter: envFilter,
		Resume:    resume,
		GitSHA:    detectGitSHA(),
		Units:     units,
	}
	metaData, _ := json.MarshalIndent(meta, "", "  ")
	if err := os.WriteFile(filepath.Join(dir, "run.json"), metaData, 0o644); err != nil {
		return nil, fmt.Errorf("writing run.json: %w", err)
	}

	// Update the "latest" symlink
	latestLink := filepath.Join(baseDir, "latest")
	os.Remove(latestLink)
	os.Symlink(dirName, latestLink)

	return &Logger{
		dir:     dir,
		waveSet: make(map[string]int),
	}, nil
}

// AssignWave sets the wave number for a batch of units starting together.
func (l *Logger) AssignWave(names []string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.waveNum++
	for _, name := range names {
		l.waveSet[name] = l.waveNum
	}
}

// IncrementWave advances the wave counter for units starting outside a batch.
func (l *Logger) IncrementWave(name string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if _, ok := l.waveSet[name]; !ok {
		l.waveNum++
		l.waveSet[name] = l.waveNum
	}
}

// LogPath returns the log file path for a unit.
func (l *Logger) LogPath(unitName string) string {
	l.mu.Lock()
	wave := l.waveSet[unitName]
	l.mu.Unlock()

	filename := fmt.Sprintf("%03d_%s.log", wave, sanitizeName(unitName))
	return filepath.Join(l.dir, filename)
}

// WriteHeader writes a self-contained header to a unit's log file.
func (l *Logger) WriteHeader(unitName, command, profile, workDir string) error {
	path := l.LogPath(unitName)
	header := fmt.Sprintf("# Unit:    %s\n# Command: %s\n# Profile: %s\n# Dir:     %s\n# Started: %s\n\n",
		unitName, command, profile, workDir, time.Now().Format(time.RFC3339))
	return os.WriteFile(path, []byte(header), 0o644)
}

// Append writes data to a unit's log file.
func (l *Logger) Append(unitName string, data []byte) error {
	path := l.LogPath(unitName)
	f, err := os.OpenFile(path, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = f.Write(data)
	return err
}

// Dir returns the log directory path.
func (l *Logger) Dir() string {
	return l.dir
}

// sanitizeName converts "platform/eks-addons" to "platform--eks-addons".
func sanitizeName(name string) string {
	return strings.ReplaceAll(name, "/", "--")
}

func detectGitSHA() string {
	// Best-effort: read .git/HEAD
	data, err := os.ReadFile(".git/HEAD")
	if err != nil {
		return ""
	}
	head := strings.TrimSpace(string(data))
	if strings.HasPrefix(head, "ref: ") {
		ref := strings.TrimPrefix(head, "ref: ")
		sha, err := os.ReadFile(filepath.Join(".git", ref))
		if err != nil {
			return ""
		}
		head = strings.TrimSpace(string(sha))
	}
	if len(head) > 7 {
		return head[:7]
	}
	return head
}
