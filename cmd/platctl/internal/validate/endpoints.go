package validate

import (
	"context"
	"fmt"
	"strings"
	"time"
)

// EndpointCheck verifies that an HTTP endpoint is reachable and returns an
// expected status code (200 or 302).
type EndpointCheck struct {
	Name string
	URL  string
	Run  CommandRunner
}

// CheckName returns the display name for skip messages.
func (e *EndpointCheck) CheckName() string { return e.Name }

// Check uses curl to probe the endpoint, parsing the response status line.
func (e *EndpointCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()
	var details []string

	out, err := e.Run(ctx, "curl", "-sI", "--max-time", "10", e.URL)
	if err != nil {
		// One retry: endpoint probes ride the tailnet, and a parallel check burst can transiently time a
		// connection out (observed exit 28 on a service that answered in <1s moments later).
		time.Sleep(2 * time.Second)
		out, err = e.Run(ctx, "curl", "-sI", "--max-time", "10", e.URL)
	}
	if err != nil {
		outStr := strings.TrimSpace(string(out))
		details = append(details,
			fmt.Sprintf("Connection to '%s' failed", e.URL),
			fmt.Sprintf("Error: %v", err),
		)
		if outStr != "" {
			details = append(details, fmt.Sprintf("Output: %s", truncate(outStr, 300)))
		}
		details = append(details,
			"Possible causes: DNS resolution failure, Gateway not programmed, TLS certificate not ready.",
			fmt.Sprintf("Run: curl -vI %s", e.URL),
			"Run: dig "+hostFromURL(e.URL),
		)
		return CheckResult{
			Name:    e.Name,
			Status:  "failed",
			Message: fmt.Sprintf("connection failed: %s", e.URL),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	// Parse the HTTP status from the first line of curl -I output
	// Expected format: "HTTP/1.1 200 OK" or "HTTP/2 302"
	outStr := string(out)
	statusCode := parseHTTPStatus(outStr)

	if statusCode == 0 {
		details = append(details,
			fmt.Sprintf("Could not parse HTTP status from response to '%s'", e.URL),
			fmt.Sprintf("Response headers:\n%s", truncate(strings.TrimSpace(outStr), 500)),
			fmt.Sprintf("Run: curl -vI %s", e.URL),
		)
		return CheckResult{
			Name:    e.Name,
			Status:  "failed",
			Message: fmt.Sprintf("unparseable response from %s", e.URL),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	if statusCode != 200 && statusCode != 302 {
		details = append(details,
			fmt.Sprintf("Unexpected HTTP status %d from '%s'", statusCode, e.URL),
			fmt.Sprintf("Response headers:\n%s", truncate(strings.TrimSpace(outStr), 500)),
			"Expected HTTP 200 or 302.",
			fmt.Sprintf("Run: curl -vI %s", e.URL),
		)
		return CheckResult{
			Name:    e.Name,
			Status:  "failed",
			Message: fmt.Sprintf("HTTP %d from %s", statusCode, e.URL),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	details = append(details, fmt.Sprintf("HTTP %d from %s", statusCode, e.URL))
	return CheckResult{
		Name:    e.Name,
		Status:  "ok",
		Message: fmt.Sprintf("HTTP %d", statusCode),
		Details: details,
		Elapsed: time.Since(start),
	}
}

// parseHTTPStatus extracts the status code from a curl -I response.
// It looks for the first line matching "HTTP/<version> <code> ...".
func parseHTTPStatus(headers string) int {
	lines := strings.Split(headers, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if !strings.HasPrefix(line, "HTTP/") {
			continue
		}
		// "HTTP/1.1 200 OK" or "HTTP/2 302"
		parts := strings.Fields(line)
		if len(parts) < 2 {
			continue
		}
		var code int
		if _, err := fmt.Sscanf(parts[1], "%d", &code); err == nil {
			return code
		}
	}
	return 0
}

// hostFromURL extracts the hostname from a URL for diagnostic suggestions.
func hostFromURL(rawURL string) string {
	// Strip scheme
	u := rawURL
	if idx := strings.Index(u, "://"); idx >= 0 {
		u = u[idx+3:]
	}
	// Strip path
	if idx := strings.IndexByte(u, '/'); idx >= 0 {
		u = u[:idx]
	}
	// Strip port
	if idx := strings.IndexByte(u, ':'); idx >= 0 {
		u = u[:idx]
	}
	return u
}
