package validate

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"
)

// DNSDelegationCheck verifies that a DNS zone's NS records at a public
// resolver match the expected nameservers (typically Route53). The expected set is DISCOVERED from the
// Route53 hosted zone's delegation set when not configured — the assigned nameservers change whenever the
// zone is recreated (every rebuild), so a hardcoded expected_ns goes stale; the config stays as an optional
// override. Profile selects the AWS profile owning the zone (for discovery).
type DNSDelegationCheck struct {
	Name       string
	Zone       string
	ExpectedNS []string // optional override; discovered from Route53 when empty
	Profile    string
	Run        CommandRunner
}

// CheckName returns the display name for skip messages.
func (d *DNSDelegationCheck) CheckName() string { return d.Name }

// discoverExpectedNS reads the hosted zone's delegation set from Route53.
func (d *DNSDelegationCheck) discoverExpectedNS(ctx context.Context) ([]string, error) {
	args := []string{
		"route53", "list-hosted-zones-by-name",
		"--dns-name", d.Zone,
		"--query", fmt.Sprintf("HostedZones[?Name=='%s.' && Config.PrivateZone==`false`].Id", d.Zone),
		"--output", "text",
	}
	if d.Profile != "" {
		args = append(args, "--profile", d.Profile)
	}
	out, err := d.Run(ctx, "aws", args...)
	if err != nil {
		return nil, fmt.Errorf("listing hosted zones: %s", strings.TrimSpace(string(out)))
	}
	zoneID := strings.TrimSpace(string(out))
	if zoneID == "" || zoneID == "None" {
		return nil, fmt.Errorf("no public hosted zone found for %s", d.Zone)
	}

	args = []string{
		"route53", "get-hosted-zone",
		"--id", zoneID,
		"--query", "DelegationSet.NameServers",
		"--output", "text",
	}
	if d.Profile != "" {
		args = append(args, "--profile", d.Profile)
	}
	out, err = d.Run(ctx, "aws", args...)
	if err != nil {
		return nil, fmt.Errorf("reading delegation set: %s", strings.TrimSpace(string(out)))
	}
	ns := strings.Fields(strings.TrimSpace(string(out)))
	if len(ns) == 0 {
		return nil, fmt.Errorf("hosted zone %s has no delegation set", zoneID)
	}
	return ns, nil
}

// Check runs dig against 8.8.8.8 and compares the returned NS records
// to the expected set. Comparison is case-insensitive and ignores trailing dots.
func (d *DNSDelegationCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()
	var details []string

	expectedNS := d.ExpectedNS
	if len(expectedNS) == 0 {
		discovered, derr := d.discoverExpectedNS(ctx)
		if derr != nil {
			return CheckResult{
				Name:    d.Name,
				Status:  "failed",
				Message: fmt.Sprintf("cannot discover Route53 NS for %s", d.Zone),
				Details: []string{derr.Error()},
				Elapsed: time.Since(start),
			}
		}
		expectedNS = discovered
	}

	out, err := d.Run(ctx, "dig", "NS", d.Zone, "@8.8.8.8", "+short")
	if err != nil {
		outStr := strings.TrimSpace(string(out))
		details = append(details,
			fmt.Sprintf("Failed to query NS records for '%s' via 8.8.8.8", d.Zone),
			fmt.Sprintf("Error: %v", err),
		)
		if outStr != "" {
			details = append(details, fmt.Sprintf("Output: %s", outStr))
		}
		details = append(details,
			"DNS resolution to 8.8.8.8 may be blocked, or the zone does not exist.",
			fmt.Sprintf("Run: dig NS %s @8.8.8.8", d.Zone),
		)
		return CheckResult{
			Name:    d.Name,
			Status:  "failed",
			Message: fmt.Sprintf("NS lookup failed for %s", d.Zone),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	outStr := strings.TrimSpace(string(out))
	if outStr == "" {
		details = append(details,
			fmt.Sprintf("No NS records returned for '%s'", d.Zone),
			"The zone may not be delegated yet or the parent zone has no NS records.",
			"Check your domain registrar or Cloudflare DNS settings for proper NS delegation.",
			fmt.Sprintf("Run: dig NS %s @8.8.8.8", d.Zone),
		)
		return CheckResult{
			Name:    d.Name,
			Status:  "failed",
			Message: fmt.Sprintf("no NS records for %s", d.Zone),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	// Parse actual NS records
	actualNS := parseNSRecords(outStr)

	// Normalize expected NS records
	expected := make([]string, len(expectedNS))
	for i, ns := range expectedNS {
		expected[i] = normalizeNS(ns)
	}
	sort.Strings(expected)

	// Compare
	matched := 0
	var missing []string
	var extra []string

	expectedSet := make(map[string]bool, len(expected))
	for _, ns := range expected {
		expectedSet[ns] = true
	}
	actualSet := make(map[string]bool, len(actualNS))
	for _, ns := range actualNS {
		actualSet[ns] = true
	}

	for _, ns := range expected {
		if actualSet[ns] {
			matched++
		} else {
			missing = append(missing, ns)
		}
	}
	for _, ns := range actualNS {
		if !expectedSet[ns] {
			extra = append(extra, ns)
		}
	}

	details = append(details,
		fmt.Sprintf("Expected NS: %s", strings.Join(expected, ", ")),
		fmt.Sprintf("Actual NS:   %s", strings.Join(actualNS, ", ")),
	)

	if len(missing) > 0 || len(extra) > 0 {
		if len(missing) > 0 {
			details = append(details, fmt.Sprintf("Missing NS records: %s", strings.Join(missing, ", ")))
		}
		if len(extra) > 0 {
			details = append(details, fmt.Sprintf("Unexpected NS records: %s", strings.Join(extra, ", ")))
		}
		details = append(details,
			"NS delegation does not match Route53. The domain registrar or upstream DNS (e.g., Cloudflare) may have stale NS records.",
			"Check your domain registrar's NS settings and update them to match the Route53 hosted zone NS records.",
			fmt.Sprintf("Run: dig NS %s @8.8.8.8", d.Zone),
			fmt.Sprintf("Run: aws route53 get-hosted-zone --id <zone-id> --query DelegationSet.NameServers"),
		)
		return CheckResult{
			Name:    d.Name,
			Status:  "failed",
			Message: fmt.Sprintf("%d/%d NS records match Route53", matched, len(expected)),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	details = append(details, "All NS records match the expected Route53 nameservers.")
	return CheckResult{
		Name:    d.Name,
		Status:  "ok",
		Message: fmt.Sprintf("%d/%d NS records match Route53", matched, len(expected)),
		Details: details,
		Elapsed: time.Since(start),
	}
}

// parseNSRecords splits dig +short output into normalized NS hostnames.
func parseNSRecords(output string) []string {
	lines := strings.Split(output, "\n")
	var records []string
	for _, line := range lines {
		ns := strings.TrimSpace(line)
		if ns == "" {
			continue
		}
		records = append(records, normalizeNS(ns))
	}
	sort.Strings(records)
	return records
}

// normalizeNS lowercases and strips the trailing dot from a nameserver hostname.
func normalizeNS(ns string) string {
	ns = strings.ToLower(strings.TrimSpace(ns))
	ns = strings.TrimSuffix(ns, ".")
	return ns
}
