package engine

import (
	"encoding/json"
	"fmt"
	"os"
	"sync"
	"time"
)

// Status represents the current state of a unit in an operation.
type Status string

const (
	StatusPending   Status = "pending"
	StatusRunning   Status = "running"
	StatusCompleted Status = "completed"
	StatusFailed    Status = "failed"
	StatusSkipped   Status = "skipped"
)

// State tracks the progress of a bootstrap or teardown operation.
type State struct {
	Operation string                `json:"operation"`
	StartedAt time.Time             `json:"started_at"`
	Units     map[string]*UnitState `json:"units"`
}

// UnitState tracks the execution state of a single unit.
type UnitState struct {
	Status     Status     `json:"status"`
	StartedAt  *time.Time `json:"started_at,omitempty"`
	FinishedAt *time.Time `json:"finished_at,omitempty"`
	Error      string     `json:"error,omitempty"`
}

// Store persists operation state across runs.
type Store interface {
	Load(path string) (*State, error)
	Save(path string, state *State) error
}

// FileStore implements Store using a JSON file on disk.
type FileStore struct {
	mu sync.Mutex
}

// NewFileStore creates a new FileStore.
func NewFileStore() *FileStore {
	return &FileStore{}
}

// Load reads state from a JSON file. Returns nil state (not an error) if the file doesn't exist.
func (fs *FileStore) Load(path string) (*State, error) {
	fs.mu.Lock()
	defer fs.mu.Unlock()

	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("reading state file %s: %w", path, err)
	}

	var state State
	if err := json.Unmarshal(data, &state); err != nil {
		return nil, fmt.Errorf("parsing state file %s: %w", path, err)
	}
	return &state, nil
}

// Save writes state to a JSON file atomically (write to temp, rename).
func (fs *FileStore) Save(path string, state *State) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()

	return writeStateFile(path, state)
}

func writeStateFile(path string, state *State) error {
	data, err := json.MarshalIndent(state, "", "  ")
	if err != nil {
		return fmt.Errorf("marshalling state: %w", err)
	}

	tmp := path + ".tmp"
	if err := os.WriteFile(tmp, data, 0o644); err != nil {
		return fmt.Errorf("writing temp state file: %w", err)
	}
	if err := os.Rename(tmp, path); err != nil {
		return fmt.Errorf("renaming state file: %w", err)
	}
	return nil
}

// NewState creates a fresh operation state for the given units.
func NewState(operation string, units []*Unit) *State {
	s := &State{
		Operation: operation,
		StartedAt: time.Now(),
		Units:     make(map[string]*UnitState, len(units)),
	}
	for _, u := range units {
		s.Units[u.Name] = &UnitState{Status: StatusPending}
	}
	return s
}

// MarkRunning transitions a unit to running status.
func (s *State) MarkRunning(name string) {
	us, ok := s.Units[name]
	if !ok {
		return
	}
	now := time.Now()
	us.Status = StatusRunning
	us.StartedAt = &now
}

// MarkCompleted transitions a unit to completed status.
func (s *State) MarkCompleted(name string) {
	us, ok := s.Units[name]
	if !ok {
		return
	}
	now := time.Now()
	us.Status = StatusCompleted
	us.FinishedAt = &now
}

// MarkFailed transitions a unit to failed status with an error message.
func (s *State) MarkFailed(name string, errMsg string) {
	us, ok := s.Units[name]
	if !ok {
		return
	}
	now := time.Now()
	us.Status = StatusFailed
	us.FinishedAt = &now
	us.Error = errMsg
}

// MarkSkipped transitions a unit to skipped status.
func (s *State) MarkSkipped(name string) {
	us, ok := s.Units[name]
	if !ok {
		return
	}
	us.Status = StatusSkipped
}

// IsComplete returns true if all units are in a terminal state.
func (s *State) IsComplete() bool {
	for _, us := range s.Units {
		if us.Status == StatusPending || us.Status == StatusRunning {
			return false
		}
	}
	return true
}

// HasFailures returns true if any unit has failed.
func (s *State) HasFailures() bool {
	for _, us := range s.Units {
		if us.Status == StatusFailed {
			return true
		}
	}
	return false
}

// PrepareForResume resets failed units to pending so they can be retried.
func (s *State) PrepareForResume() {
	for _, us := range s.Units {
		if us.Status == StatusFailed || us.Status == StatusSkipped {
			us.Status = StatusPending
			us.Error = ""
			us.StartedAt = nil
			us.FinishedAt = nil
		}
	}
}
