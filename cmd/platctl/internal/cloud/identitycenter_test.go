package cloud

import (
	"context"
	"errors"
	"testing"
	"time"
)

func TestPollToTerminal(t *testing.T) {
	t.Run("polls IN_PROGRESS until SUCCEEDED", func(t *testing.T) {
		calls := 0
		describe := func(context.Context) (assignmentStatus, error) {
			calls++
			if calls < 3 {
				return assignmentStatus{Status: "IN_PROGRESS"}, nil
			}
			return assignmentStatus{Status: "SUCCEEDED"}, nil
		}
		s, err := pollToTerminal(context.Background(), time.Millisecond, describe)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if s.Status != "SUCCEEDED" {
			t.Errorf("status = %s, want SUCCEEDED", s.Status)
		}
		if calls != 3 {
			t.Errorf("describe called %d times, want 3", calls)
		}
	})

	t.Run("returns terminal FAILED without erroring (caller maps it)", func(t *testing.T) {
		describe := func(context.Context) (assignmentStatus, error) {
			return assignmentStatus{Status: "FAILED", FailureReason: "boom"}, nil
		}
		s, err := pollToTerminal(context.Background(), time.Millisecond, describe)
		if err != nil {
			t.Fatalf("FAILED is terminal, poll should not error: %v", err)
		}
		if s.Status != "FAILED" {
			t.Errorf("status = %s, want FAILED", s.Status)
		}
	})

	t.Run("propagates a describe error", func(t *testing.T) {
		want := errors.New("aws down")
		describe := func(context.Context) (assignmentStatus, error) {
			return assignmentStatus{}, want
		}
		if _, err := pollToTerminal(context.Background(), time.Millisecond, describe); !errors.Is(err, want) {
			t.Errorf("want the describe error, got %v", err)
		}
	})

	t.Run("times out while stuck IN_PROGRESS", func(t *testing.T) {
		describe := func(context.Context) (assignmentStatus, error) {
			return assignmentStatus{Status: "IN_PROGRESS"}, nil
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Millisecond)
		defer cancel()
		_, err := pollToTerminal(ctx, time.Millisecond, describe)
		if err == nil || !errors.Is(err, context.DeadlineExceeded) {
			t.Errorf("want a deadline-exceeded timeout, got %v", err)
		}
	})
}
