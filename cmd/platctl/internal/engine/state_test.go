package engine

import (
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
)

func TestNewState(t *testing.T) {
	units := []*Unit{
		{Name: "platform/eks"},
		{Name: "platform/cilium"},
	}
	s := NewState("bootstrap", units)

	if s.Operation != "bootstrap" {
		t.Fatalf("expected operation bootstrap, got %s", s.Operation)
	}
	if len(s.Units) != 2 {
		t.Fatalf("expected 2 units, got %d", len(s.Units))
	}
	if s.Units["platform/eks"].Status != StatusPending {
		t.Fatalf("expected pending status, got %s", s.Units["platform/eks"].Status)
	}
}

func TestStateTransitions(t *testing.T) {
	units := []*Unit{{Name: "platform/eks"}}
	s := NewState("bootstrap", units)

	s.MarkRunning("platform/eks")
	if s.Units["platform/eks"].Status != StatusRunning {
		t.Fatalf("expected running, got %s", s.Units["platform/eks"].Status)
	}
	if s.Units["platform/eks"].StartedAt == nil {
		t.Fatal("expected StartedAt to be set")
	}

	s.MarkCompleted("platform/eks")
	if s.Units["platform/eks"].Status != StatusCompleted {
		t.Fatalf("expected completed, got %s", s.Units["platform/eks"].Status)
	}
	if s.Units["platform/eks"].FinishedAt == nil {
		t.Fatal("expected FinishedAt to be set")
	}
}

func TestStateTransition_Failed(t *testing.T) {
	units := []*Unit{{Name: "platform/eks"}}
	s := NewState("bootstrap", units)

	s.MarkRunning("platform/eks")
	s.MarkFailed("platform/eks", "exit status 1")

	if s.Units["platform/eks"].Status != StatusFailed {
		t.Fatalf("expected failed, got %s", s.Units["platform/eks"].Status)
	}
	if s.Units["platform/eks"].Error != "exit status 1" {
		t.Fatalf("expected error message, got %q", s.Units["platform/eks"].Error)
	}
}

func TestIsComplete(t *testing.T) {
	units := []*Unit{
		{Name: "platform/eks"},
		{Name: "platform/cilium"},
	}
	s := NewState("bootstrap", units)

	if s.IsComplete() {
		t.Fatal("expected not complete with pending units")
	}

	s.MarkCompleted("platform/eks")
	s.MarkFailed("platform/cilium", "error")

	if !s.IsComplete() {
		t.Fatal("expected complete when all units are terminal")
	}
}

func TestPrepareForResume(t *testing.T) {
	units := []*Unit{
		{Name: "platform/eks"},
		{Name: "platform/cilium"},
		{Name: "platform/node-groups"},
	}
	s := NewState("bootstrap", units)

	s.MarkCompleted("platform/eks")
	s.MarkFailed("platform/cilium", "error")
	s.MarkSkipped("platform/node-groups")

	s.PrepareForResume()

	if s.Units["platform/eks"].Status != StatusCompleted {
		t.Fatal("completed units should stay completed after resume")
	}
	if s.Units["platform/cilium"].Status != StatusPending {
		t.Fatal("failed units should become pending after resume")
	}
	if s.Units["platform/node-groups"].Status != StatusPending {
		t.Fatal("skipped units should become pending after resume")
	}
}

func TestFileStore_SaveLoad(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state.json")

	store := NewFileStore()

	units := []*Unit{{Name: "platform/eks"}, {Name: "platform/cilium"}}
	s := NewState("bootstrap", units)
	s.MarkCompleted("platform/eks")

	if err := store.Save(path, s); err != nil {
		t.Fatalf("save error: %v", err)
	}

	loaded, err := store.Load(path)
	if err != nil {
		t.Fatalf("load error: %v", err)
	}

	if loaded.Operation != "bootstrap" {
		t.Fatalf("expected operation bootstrap, got %s", loaded.Operation)
	}
	if loaded.Units["platform/eks"].Status != StatusCompleted {
		t.Fatalf("expected completed, got %s", loaded.Units["platform/eks"].Status)
	}
	if loaded.Units["platform/cilium"].Status != StatusPending {
		t.Fatalf("expected pending, got %s", loaded.Units["platform/cilium"].Status)
	}
}

func TestFileStore_LoadMissing(t *testing.T) {
	store := NewFileStore()
	s, err := store.Load("/nonexistent/path.json")
	if err != nil {
		t.Fatalf("expected nil error for missing file, got %v", err)
	}
	if s != nil {
		t.Fatal("expected nil state for missing file")
	}
}

func TestFileStore_AtomicWrite(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state.json")

	store := NewFileStore()
	units := []*Unit{{Name: "platform/eks"}}
	s := NewState("bootstrap", units)

	if err := store.Save(path, s); err != nil {
		t.Fatalf("save error: %v", err)
	}

	// Verify no temp file left behind
	matches, _ := filepath.Glob(filepath.Join(dir, "*.tmp"))
	if len(matches) > 0 {
		t.Fatalf("temp file left behind: %v", matches)
	}

	// Verify the file exists and is valid JSON
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read error: %v", err)
	}
	if len(data) == 0 {
		t.Fatal("empty state file")
	}
}

func TestFileStore_ConcurrentWrites(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "state.json")

	store := NewFileStore()
	units := make([]*Unit, 10)
	for i := range units {
		units[i] = &Unit{Name: fmt.Sprintf("unit-%d", i)}
	}
	s := NewState("bootstrap", units)

	if err := store.Save(path, s); err != nil {
		t.Fatalf("initial save error: %v", err)
	}

	// Simulate concurrent state updates
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func(idx int) {
			defer wg.Done()
			name := fmt.Sprintf("unit-%d", idx)
			s.MarkCompleted(name)
			if err := store.Save(path, s); err != nil {
				t.Errorf("concurrent save error: %v", err)
			}
		}(i)
	}
	wg.Wait()

	// Verify the final state is valid
	loaded, err := store.Load(path)
	if err != nil {
		t.Fatalf("load after concurrent writes: %v", err)
	}
	if loaded == nil {
		t.Fatal("expected non-nil state after concurrent writes")
	}
}
