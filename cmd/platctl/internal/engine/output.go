package engine

import (
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
	"sync"
	"time"
)

// OutputMode controls how unit execution is displayed to the terminal.
type OutputMode int

const (
	// OutputDefault shows a live status table with one line per unit.
	OutputDefault OutputMode = iota
	// OutputVerbose shows the default view plus terragrunt resource change summaries.
	OutputVerbose
	// OutputStream shows full terragrunt output, prefixed with unit name.
	OutputStream
)

// Output manages terminal display during engine execution.
type Output struct {
	mu       sync.Mutex
	mode     OutputMode
	writer   io.Writer
	statuses map[string]*unitDisplay
	started  time.Time
}

type unitDisplay struct {
	Name      string
	Status    Status
	StartedAt time.Time
	Duration  time.Duration
	Error     string
}

// NewOutput creates a terminal output handler.
func NewOutput(mode OutputMode) *Output {
	return &Output{
		mode:     mode,
		writer:   os.Stdout,
		statuses: make(map[string]*unitDisplay),
		started:  time.Now(),
	}
}

// UnitStarted records that a unit has begun execution.
func (o *Output) UnitStarted(name string) {
	o.mu.Lock()
	defer o.mu.Unlock()
	o.statuses[name] = &unitDisplay{
		Name:      name,
		Status:    StatusRunning,
		StartedAt: time.Now(),
	}
	if o.mode == OutputStream {
		fmt.Fprintf(o.writer, "[%s] started\n", name)
	}
}

// UnitCompleted records that a unit has finished successfully.
func (o *Output) UnitCompleted(name string, duration time.Duration) {
	o.mu.Lock()
	defer o.mu.Unlock()
	if d, ok := o.statuses[name]; ok {
		d.Status = StatusCompleted
		d.Duration = duration
	}
	fmt.Fprintf(o.writer, "ok %s (%s)\n", name, duration.Round(time.Second))
}

// UnitFailed records that a unit has failed.
func (o *Output) UnitFailed(name string, duration time.Duration, errMsg string) {
	o.mu.Lock()
	defer o.mu.Unlock()
	if d, ok := o.statuses[name]; ok {
		d.Status = StatusFailed
		d.Duration = duration
		d.Error = errMsg
	}
	fmt.Fprintf(o.writer, "!! %s FAILED (%s)\n", name, duration.Round(time.Second))
}

// UnitSkipped records that a unit was skipped due to upstream failure.
func (o *Output) UnitSkipped(name string) {
	o.mu.Lock()
	defer o.mu.Unlock()
	if d, ok := o.statuses[name]; ok {
		d.Status = StatusSkipped
	} else {
		o.statuses[name] = &unitDisplay{Name: name, Status: StatusSkipped}
	}
}

// StreamLine writes a line of unit output in stream mode.
func (o *Output) StreamLine(name, line string) {
	if o.mode != OutputStream {
		return
	}
	o.mu.Lock()
	defer o.mu.Unlock()
	fmt.Fprintf(o.writer, "[%s] %s\n", name, line)
}

// VerboseSummary prints a resource change summary after a unit completes.
func (o *Output) VerboseSummary(name, summary string) {
	if o.mode < OutputVerbose {
		return
	}
	o.mu.Lock()
	defer o.mu.Unlock()
	fmt.Fprintf(o.writer, "   %s: %s\n", name, summary)
}

// PrintSummary prints a final summary table of all unit statuses.
func (o *Output) PrintSummary() {
	o.mu.Lock()
	defer o.mu.Unlock()

	elapsed := time.Since(o.started).Round(time.Second)

	fmt.Fprintln(o.writer)
	fmt.Fprintf(o.writer, "Summary (%s elapsed):\n", elapsed)

	names := make([]string, 0, len(o.statuses))
	for name := range o.statuses {
		names = append(names, name)
	}
	sort.Strings(names)

	var completed, failed, skipped int
	for _, name := range names {
		d := o.statuses[name]
		sym := statusSym(d.Status)
		dur := ""
		if d.Duration > 0 {
			dur = fmt.Sprintf("  %s", d.Duration.Round(time.Second))
		}
		errInfo := ""
		if d.Error != "" {
			// Truncate error for summary
			msg := d.Error
			if len(msg) > 80 {
				msg = msg[:77] + "..."
			}
			errInfo = fmt.Sprintf("  %s", msg)
		}
		fmt.Fprintf(o.writer, "  %s %-35s%s%s\n", sym, name, dur, errInfo)

		switch d.Status {
		case StatusCompleted:
			completed++
		case StatusFailed:
			failed++
		case StatusSkipped:
			skipped++
		}
	}

	fmt.Fprintf(o.writer, "\n  Completed: %d  Failed: %d  Skipped: %d\n", completed, failed, skipped)
}

// PrintFailureDetail prints the last N lines of a failed unit's log.
func (o *Output) PrintFailureDetail(name, logPath string, lastLines int) {
	fmt.Fprintf(o.writer, "\n!! %s failed\n", name)

	if logPath == "" {
		return
	}

	data, err := os.ReadFile(logPath)
	if err != nil {
		fmt.Fprintf(o.writer, "   (could not read log: %v)\n", err)
		return
	}

	lines := strings.Split(string(data), "\n")
	start := 0
	if len(lines) > lastLines {
		start = len(lines) - lastLines
	}

	fmt.Fprintln(o.writer, "   Last output:")
	fmt.Fprintln(o.writer, "   "+strings.Repeat("-", 60))
	for _, line := range lines[start:] {
		if line != "" {
			fmt.Fprintf(o.writer, "   %s\n", line)
		}
	}
	fmt.Fprintln(o.writer, "   "+strings.Repeat("-", 60))
	fmt.Fprintf(o.writer, "   Full log: %s\n", logPath)
}

func statusSym(s Status) string {
	switch s {
	case StatusCompleted:
		return "ok"
	case StatusFailed:
		return "!!"
	case StatusSkipped:
		return "--"
	case StatusRunning:
		return ">>"
	default:
		return "  "
	}
}
