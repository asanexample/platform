package validate

import (
	"context"
	"fmt"
	"strings"
	"testing"
)

func xtenantJSON(items ...string) []byte {
	return []byte(fmt.Sprintf(`{"items":[%s]}`, strings.Join(items, ",")))
}

func xtenant(name, team, tname, env, synced, ready string) string {
	return fmt.Sprintf(`{
		"metadata":{"name":%q},
		"spec":{"team":%q,"name":%q,"environment":%q},
		"status":{"conditions":[
			{"type":"Synced","status":%q,"reason":"ReconcileSuccess"},
			{"type":"Ready","status":%q,"reason":"Creating"}
		]}}`, name, team, tname, env, synced, ready)
}

func TestTenantCheck_V2_AllReady(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "kubectl --context preprod get xtenants.platform.refplat.org",
			out: xtenantJSON(
				xtenant("alpha-demo-dev", "alpha", "demo", "dev", "True", "True"),
				xtenant("bravo-demo-dev", "bravo", "demo", "dev", "True", "True"),
			)},
		mockCall{prefix: "kubectl --context preprod get teams.platform.refplat.org",
			out: []byte("team.platform.refplat.org/alpha\nteam.platform.refplat.org/bravo\n")},
		// v2 namespace = <team>-<name>-<env>
		mockCall{prefix: "kubectl --context preprod get resourcequota,networkpolicy -n alpha-demo-dev",
			out: []byte("resourcequota/tenant-quota\nnetworkpolicy/default-deny-ingress\n")},
		mockCall{prefix: "kubectl --context preprod get ciliumnetworkpolicy -n alpha-demo-dev",
			out: []byte("ciliumnetworkpolicy.cilium.io/allow-gateway-envoy\n")},
		mockCall{prefix: "kubectl --context preprod get resourcequota,networkpolicy -n bravo-demo-dev",
			out: []byte("resourcequota/tenant-quota\nnetworkpolicy/default-deny-ingress\n")},
		mockCall{prefix: "kubectl --context preprod get ciliumnetworkpolicy -n bravo-demo-dev",
			out: []byte("ciliumnetworkpolicy.cilium.io/allow-gateway-envoy\n")},
	)

	res := (&TenantCheck{Name: "preprod/crossplane/tenants", KubeContext: "preprod", Run: run}).Check(context.Background())
	if res.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s %v", res.Status, res.Message, res.Details)
	}
	if !strings.Contains(res.Message, "2/2") {
		t.Fatalf("expected 2/2 tenants in message, got %q", res.Message)
	}
}

func TestTenantCheck_V2_NotReadyAndMissingTeam(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "kubectl --context preprod get xtenants.platform.refplat.org",
			out: xtenantJSON(
				xtenant("alpha-demo-dev", "alpha", "demo", "dev", "True", "False"),
				xtenant("bravo-demo-dev", "bravo", "demo", "dev", "True", "True"),
			)},
		// bravo's Team CR is missing — must be flagged even though the XTenant is Ready.
		mockCall{prefix: "kubectl --context preprod get teams.platform.refplat.org",
			out: []byte("team.platform.refplat.org/alpha\n")},
		mockCall{prefix: "kubectl --context preprod get resourcequota,networkpolicy -n bravo-demo-dev",
			out: []byte("resourcequota/tenant-quota\nnetworkpolicy/default-deny-ingress\n")},
		mockCall{prefix: "kubectl --context preprod get ciliumnetworkpolicy -n bravo-demo-dev",
			out: []byte("ciliumnetworkpolicy.cilium.io/allow-gateway-envoy\n")},
	)

	res := (&TenantCheck{Name: "t", KubeContext: "preprod", Run: run}).Check(context.Background())
	if res.Status != "failed" {
		t.Fatalf("expected failed, got %s: %s", res.Status, res.Message)
	}
	joined := strings.Join(res.Details, "; ")
	if !strings.Contains(joined, "alpha-demo-dev: not Ready") {
		t.Fatalf("expected alpha not-Ready detail, got %v", res.Details)
	}
	if !strings.Contains(joined, `Team CR "bravo" not projected`) {
		t.Fatalf("expected missing-Team detail for bravo, got %v", res.Details)
	}
}

func TestTenantCheck_NoTenantAPI_Skips(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "kubectl --context platform get xtenants.platform.refplat.org",
			out: []byte(`error: the server doesn't have a resource type "xtenants"`),
			err: fmt.Errorf("exit status 1")},
	)

	res := (&TenantCheck{Name: "platform/crossplane/tenants", KubeContext: "platform", Run: run}).Check(context.Background())
	if res.Status != "ok" {
		t.Fatalf("clusters without the tenant API must skip, got %s: %s", res.Status, res.Message)
	}
	if !strings.Contains(res.Message, "no tenant API") {
		t.Fatalf("expected skip message, got %q", res.Message)
	}
}

func TestTenantCheck_NoClaims_Fails(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "kubectl --context preprod get xtenants.platform.refplat.org",
			out: []byte(`{"items":[]}`)},
	)

	res := (&TenantCheck{Name: "t", KubeContext: "preprod", Run: run}).Check(context.Background())
	if res.Status != "failed" {
		t.Fatalf("tenant API with zero claims must fail (claims not synced), got %s", res.Status)
	}
}

func TestDNSDelegationCheck_DiscoversExpectedNSFromRoute53(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "aws route53 list-hosted-zones-by-name --dns-name example.org",
			out: []byte("/hostedzone/Z123\n")},
		mockCall{prefix: "aws route53 get-hosted-zone --id /hostedzone/Z123",
			out: []byte("ns-1.awsdns-01.com\tns-2.awsdns-02.net\n")},
		mockCall{prefix: "dig NS example.org",
			out: []byte("ns-1.awsdns-01.com.\nns-2.awsdns-02.net.\n")},
	)

	res := (&DNSDelegationCheck{Name: "dns/example.org", Zone: "example.org", Profile: "platform", Run: run}).Check(context.Background())
	if res.Status != "ok" {
		t.Fatalf("expected ok via discovered NS, got %s: %s %v", res.Status, res.Message, res.Details)
	}
}

func TestDNSDelegationCheck_DiscoveryMismatchFails(t *testing.T) {
	run := newMockRunner(
		mockCall{prefix: "aws route53 list-hosted-zones-by-name --dns-name example.org",
			out: []byte("/hostedzone/Z123\n")},
		mockCall{prefix: "aws route53 get-hosted-zone --id /hostedzone/Z123",
			out: []byte("ns-1.awsdns-01.com\tns-2.awsdns-02.net\n")},
		// Public DNS still serves the PREVIOUS zone's nameservers (stale registrar delegation).
		mockCall{prefix: "dig NS example.org",
			out: []byte("ns-9.awsdns-99.org.\n")},
	)

	res := (&DNSDelegationCheck{Name: "dns/example.org", Zone: "example.org", Run: run}).Check(context.Background())
	if res.Status != "failed" {
		t.Fatalf("expected mismatch failure, got %s: %s", res.Status, res.Message)
	}
}

func TestTGWAttachmentCheck_DiscoveryModeSkipsTombstones(t *testing.T) {
	var seen string
	run := func(ctx context.Context, name string, args ...string) ([]byte, error) {
		seen = name + " " + strings.Join(args, " ")
		return []byte(`{"TransitGatewayAttachments":[
			{"TransitGatewayAttachmentId":"a1","State":"available","ResourceId":"vpc-1","ResourceType":"vpc"},
			{"TransitGatewayAttachmentId":"a2","State":"available","ResourceId":"vpc-2","ResourceType":"vpc"},
			{"TransitGatewayAttachmentId":"old","State":"deleted","ResourceId":"vpc-0","ResourceType":"vpc"}
		]}`), nil
	}

	res := (&TGWAttachmentCheck{Name: "tgw", Auth: map[string]string{"profile": "platform"}, Run: run}).Check(context.Background())
	if res.Status != "ok" {
		t.Fatalf("expected ok, got %s: %s %v", res.Status, res.Message, res.Details)
	}
	if strings.Contains(seen, "transit-gateway-id") {
		t.Fatalf("discovery mode must not filter by a TGW id, ran: %s", seen)
	}
	if !strings.Contains(res.Message, "2/2") {
		t.Fatalf("tombstoned attachment must not count, got %q", res.Message)
	}
}
