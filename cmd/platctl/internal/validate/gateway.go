package validate

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"github.com/gangster/platform/cmd/platctl/internal/cloud"
)

// GatewayHealthCheck verifies the full gateway stack: GatewayClass, Gateway,
// ClusterIssuer, Certificate, and the backing NLB health.
type GatewayHealthCheck struct {
	Name             string
	KubeContext      string
	GatewayClassName string
	GatewayName      string
	GatewayNamespace string
	CertName         string
	Auth             map[string]string
	Run              CommandRunner
}

// CheckName returns the display name for skip messages.
func (g *GatewayHealthCheck) CheckName() string { return g.Name }

// --- minimal JSON structs for kubectl output ---

type k8sCondition struct {
	Type               string `json:"type"`
	Status             string `json:"status"`
	Reason             string `json:"reason"`
	Message            string `json:"message"`
	LastTransitionTime string `json:"lastTransitionTime"`
}

type k8sGatewayClassStatus struct {
	Conditions []k8sCondition `json:"conditions"`
}

type k8sGatewayClass struct {
	Status k8sGatewayClassStatus `json:"status"`
}

type k8sGatewayAddress struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

type k8sGatewayStatus struct {
	Conditions []k8sCondition      `json:"conditions"`
	Addresses  []k8sGatewayAddress `json:"addresses"`
}

type k8sGateway struct {
	Status k8sGatewayStatus `json:"status"`
}

type k8sIssuerStatus struct {
	Conditions []k8sCondition `json:"conditions"`
}

type k8sClusterIssuer struct {
	Status k8sIssuerStatus `json:"status"`
}

type k8sCertStatus struct {
	Conditions []k8sCondition `json:"conditions"`
}

type k8sCertificate struct {
	Status k8sCertStatus `json:"status"`
}

type elbLoadBalancer struct {
	LoadBalancerArn string      `json:"LoadBalancerArn"`
	DNSName         string      `json:"DNSName"`
	State           elbLBState  `json:"State"`
}

type elbLBState struct {
	Code string `json:"Code"`
}

type elbDescribeOutput struct {
	LoadBalancers []elbLoadBalancer `json:"LoadBalancers"`
}

type elbTargetGroup struct {
	TargetGroupArn string `json:"TargetGroupArn"`
}

type elbTargetGroupsOutput struct {
	TargetGroups []elbTargetGroup `json:"TargetGroups"`
}

type elbTargetHealth struct {
	Target      elbTarget      `json:"Target"`
	TargetHealth elbHealthDesc `json:"TargetHealth"`
}

type elbTarget struct {
	Id   string `json:"Id"`
	Port int    `json:"Port"`
}

type elbHealthDesc struct {
	State       string `json:"State"`
	Reason      string `json:"Reason"`
	Description string `json:"Description"`
}

type elbTargetHealthOutput struct {
	TargetHealthDescriptions []elbTargetHealth `json:"TargetHealthDescriptions"`
}

// Check performs sequential sub-checks across the gateway stack.
func (g *GatewayHealthCheck) Check(ctx context.Context) CheckResult {
	start := time.Now()
	var details []string

	region := cloud.RegionFromAuth(g.Auth)
	profile := g.Auth["profile"]

	// 1. GatewayClass
	gwClassName := g.GatewayClassName
	if gwClassName == "" {
		gwClassName = "cilium"
	}
	out, err := g.Run(ctx, "kubectl", "--context", g.KubeContext,
		"get", "gatewayclass", gwClassName, "-o", "json")
	if err != nil {
		details = append(details,
			fmt.Sprintf("Failed to get GatewayClass '%s': %s", gwClassName, strings.TrimSpace(string(out))),
			fmt.Sprintf("Error: %v", err),
			fmt.Sprintf("GatewayClass '%s' does not exist. The Cilium operator failed to create it.", gwClassName),
			"Run: kubectl rollout restart deployment/cilium-operator -n kube-system",
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "GatewayClass 'cilium' not found",
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	var gwClass k8sGatewayClass
	if err := json.Unmarshal(out, &gwClass); err != nil {
		details = append(details,
			fmt.Sprintf("Failed to parse GatewayClass JSON: %v", err),
			fmt.Sprintf("Raw output: %s", truncate(string(out), 500)),
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "GatewayClass JSON parse error",
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	if !conditionTrue(gwClass.Status.Conditions, "Accepted") {
		details = append(details,
			fmt.Sprintf("GatewayClass 'cilium' conditions: %s", formatConditions(gwClass.Status.Conditions)),
			"GatewayClass is not Accepted. The Cilium operator may be unhealthy or misconfigured.",
			"Run: kubectl rollout restart deployment/cilium-operator -n kube-system",
			"Run: kubectl logs -n kube-system -l app.kubernetes.io/name=cilium-operator --tail=50",
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "GatewayClass 'cilium' not Accepted",
			Details: details,
			Elapsed: time.Since(start),
		}
	}
	details = append(details, "GatewayClass 'cilium': Accepted=True")

	// 2. Gateway
	out, err = g.Run(ctx, "kubectl", "--context", g.KubeContext,
		"get", "gateway", g.GatewayName, "-n", g.GatewayNamespace, "-o", "json")
	if err != nil {
		details = append(details,
			fmt.Sprintf("Failed to get Gateway '%s/%s': %s", g.GatewayNamespace, g.GatewayName, strings.TrimSpace(string(out))),
			fmt.Sprintf("Error: %v", err),
			fmt.Sprintf("Run: kubectl describe gateway %s -n %s --context %s", g.GatewayName, g.GatewayNamespace, g.KubeContext),
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: fmt.Sprintf("Gateway '%s/%s' not found", g.GatewayNamespace, g.GatewayName),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	var gw k8sGateway
	if err := json.Unmarshal(out, &gw); err != nil {
		details = append(details,
			fmt.Sprintf("Failed to parse Gateway JSON: %v", err),
			fmt.Sprintf("Raw output: %s", truncate(string(out), 500)),
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "Gateway JSON parse error",
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	if !conditionTrue(gw.Status.Conditions, "Programmed") {
		details = append(details,
			fmt.Sprintf("Gateway '%s/%s' conditions: %s", g.GatewayNamespace, g.GatewayName, formatConditions(gw.Status.Conditions)),
			"Gateway is not Programmed. Cilium may have failed to reconcile the Gateway resource.",
			fmt.Sprintf("Run: kubectl describe gateway %s -n %s --context %s", g.GatewayName, g.GatewayNamespace, g.KubeContext),
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: fmt.Sprintf("Gateway '%s/%s' not Programmed", g.GatewayNamespace, g.GatewayName),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	var gatewayAddress string
	if len(gw.Status.Addresses) > 0 {
		gatewayAddress = gw.Status.Addresses[0].Value
	}
	details = append(details, fmt.Sprintf("Gateway '%s/%s': Programmed=True, address=%s", g.GatewayNamespace, g.GatewayName, gatewayAddress))

	// 3. ClusterIssuer
	out, err = g.Run(ctx, "kubectl", "--context", g.KubeContext,
		"get", "clusterissuer", "letsencrypt-prod", "-o", "json")
	if err != nil {
		details = append(details,
			fmt.Sprintf("Failed to get ClusterIssuer 'letsencrypt-prod': %s", strings.TrimSpace(string(out))),
			fmt.Sprintf("Error: %v", err),
			"Run: kubectl describe clusterissuer letsencrypt-prod",
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "ClusterIssuer 'letsencrypt-prod' not found",
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	var issuer k8sClusterIssuer
	if err := json.Unmarshal(out, &issuer); err != nil {
		details = append(details,
			fmt.Sprintf("Failed to parse ClusterIssuer JSON: %v", err),
			fmt.Sprintf("Raw output: %s", truncate(string(out), 500)),
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "ClusterIssuer JSON parse error",
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	if !conditionTrue(issuer.Status.Conditions, "Ready") {
		msg := conditionMessage(issuer.Status.Conditions, "Ready")
		details = append(details,
			fmt.Sprintf("ClusterIssuer 'letsencrypt-prod' is not Ready: %s", msg),
			"The ACME account registration may have failed or the solver is misconfigured.",
			"Run: kubectl describe clusterissuer letsencrypt-prod",
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "ClusterIssuer 'letsencrypt-prod' not Ready",
			Details: details,
			Elapsed: time.Since(start),
		}
	}
	details = append(details, "ClusterIssuer 'letsencrypt-prod': Ready=True")

	// 4. Certificate
	out, err = g.Run(ctx, "kubectl", "--context", g.KubeContext,
		"get", "certificate", g.CertName, "-n", g.GatewayNamespace, "-o", "json")
	if err != nil {
		details = append(details,
			fmt.Sprintf("Failed to get Certificate '%s/%s': %s", g.GatewayNamespace, g.CertName, strings.TrimSpace(string(out))),
			fmt.Sprintf("Error: %v", err),
			fmt.Sprintf("Run: kubectl describe certificate %s -n %s", g.CertName, g.GatewayNamespace),
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: fmt.Sprintf("Certificate '%s/%s' not found", g.GatewayNamespace, g.CertName),
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	var cert k8sCertificate
	if err := json.Unmarshal(out, &cert); err != nil {
		details = append(details,
			fmt.Sprintf("Failed to parse Certificate JSON: %v", err),
			fmt.Sprintf("Raw output: %s", truncate(string(out), 500)),
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "Certificate JSON parse error",
			Details: details,
			Elapsed: time.Since(start),
		}
	}

	if !conditionTrue(cert.Status.Conditions, "Ready") {
		reason := conditionReason(cert.Status.Conditions, "Ready")
		msg := conditionMessage(cert.Status.Conditions, "Ready")
		details = append(details,
			fmt.Sprintf("Certificate '%s/%s' is not Ready", g.GatewayNamespace, g.CertName),
			fmt.Sprintf("Reason: %s", reason),
			fmt.Sprintf("Message: %s", msg),
			"This may indicate a Let's Encrypt rate limit, DNS solver failure, or missing HTTP solver ingress.",
			fmt.Sprintf("Run: kubectl describe certificate %s -n %s", g.CertName, g.GatewayNamespace),
		)
		return CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: fmt.Sprintf("Certificate '%s/%s' not Ready: %s", g.GatewayNamespace, g.CertName, reason),
			Details: details,
			Elapsed: time.Since(start),
		}
	}
	details = append(details, fmt.Sprintf("Certificate '%s/%s': Ready=True", g.GatewayNamespace, g.CertName))

	// 5. NLB health (only if gateway has an address)
	if gatewayAddress != "" {
		nlbResult := g.checkNLBHealth(ctx, gatewayAddress, profile, region, details)
		if nlbResult != nil {
			nlbResult.Elapsed = time.Since(start)
			return *nlbResult
		}
		details = append(details, fmt.Sprintf("NLB '%s': state=active, targets healthy", gatewayAddress))
	}

	return CheckResult{
		Name:    g.Name,
		Status:  "ok",
		Message: fmt.Sprintf("gateway stack healthy (address: %s)", gatewayAddress),
		Details: details,
		Elapsed: time.Since(start),
	}
}

// checkNLBHealth verifies the NLB backing the gateway is active and targets are healthy.
// Returns nil on success, or a failed CheckResult.
func (g *GatewayHealthCheck) checkNLBHealth(ctx context.Context, hostname, profile, region string, details []string) *CheckResult {
	// Describe load balancers matching the gateway hostname
	args := []string{
		"elbv2", "describe-load-balancers",
		"--query", fmt.Sprintf("LoadBalancers[?DNSName=='%s']", hostname),
		"--region", region,
	}
	if profile != "" {
		args = append(args, "--profile", profile)
	}

	out, err := g.Run(ctx, "aws", args...)
	if err != nil {
		details = append(details,
			fmt.Sprintf("Failed to describe load balancers for hostname '%s': %s", hostname, strings.TrimSpace(string(out))),
			fmt.Sprintf("Error: %v", err),
			"Run: aws elbv2 describe-load-balancers --region "+region,
		)
		return &CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "NLB lookup failed",
			Details: details,
		}
	}

	var lbs []elbLoadBalancer
	if err := json.Unmarshal(out, &lbs); err != nil {
		details = append(details,
			fmt.Sprintf("Failed to parse ELB JSON: %v", err),
			fmt.Sprintf("Raw output: %s", truncate(string(out), 500)),
		)
		return &CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "NLB JSON parse error",
			Details: details,
		}
	}

	if len(lbs) == 0 {
		details = append(details,
			fmt.Sprintf("No load balancer found with DNS name '%s'", hostname),
			"The NLB may have been deleted or the DNS name does not match.",
			"Run: aws elbv2 describe-load-balancers --region "+region,
		)
		return &CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "NLB not found for gateway address",
			Details: details,
		}
	}

	lb := lbs[0]
	if lb.State.Code != "active" {
		details = append(details,
			fmt.Sprintf("NLB state is '%s', expected 'active'", lb.State.Code),
			fmt.Sprintf("NLB ARN: %s", lb.LoadBalancerArn),
			"The load balancer may still be provisioning or is in a failed state.",
			"Run: aws elbv2 describe-load-balancers --names <nlb-name> --region "+region,
		)
		return &CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: fmt.Sprintf("NLB state is '%s'", lb.State.Code),
			Details: details,
		}
	}

	// Get target groups for this NLB
	tgArgs := []string{
		"elbv2", "describe-target-groups",
		"--load-balancer-arn", lb.LoadBalancerArn,
		"--region", region,
	}
	if profile != "" {
		tgArgs = append(tgArgs, "--profile", profile)
	}

	out, err = g.Run(ctx, "aws", tgArgs...)
	if err != nil {
		details = append(details,
			fmt.Sprintf("Failed to describe target groups: %s", strings.TrimSpace(string(out))),
			fmt.Sprintf("Error: %v", err),
		)
		return &CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "NLB target group lookup failed",
			Details: details,
		}
	}

	var tgOutput elbTargetGroupsOutput
	if err := json.Unmarshal(out, &tgOutput); err != nil {
		details = append(details,
			fmt.Sprintf("Failed to parse target groups JSON: %v", err),
			fmt.Sprintf("Raw output: %s", truncate(string(out), 500)),
		)
		return &CheckResult{
			Name:    g.Name,
			Status:  "failed",
			Message: "target groups JSON parse error",
			Details: details,
		}
	}

	// Check target health for each target group
	for _, tg := range tgOutput.TargetGroups {
		thArgs := []string{
			"elbv2", "describe-target-health",
			"--target-group-arn", tg.TargetGroupArn,
			"--region", region,
		}
		if profile != "" {
			thArgs = append(thArgs, "--profile", profile)
		}

		out, err = g.Run(ctx, "aws", thArgs...)
		if err != nil {
			details = append(details,
				fmt.Sprintf("Failed to describe target health for %s: %s", tg.TargetGroupArn, strings.TrimSpace(string(out))),
				fmt.Sprintf("Error: %v", err),
			)
			return &CheckResult{
				Name:    g.Name,
				Status:  "failed",
				Message: "NLB target health check failed",
				Details: details,
			}
		}

		var thOutput elbTargetHealthOutput
		if err := json.Unmarshal(out, &thOutput); err != nil {
			details = append(details,
				fmt.Sprintf("Failed to parse target health JSON: %v", err),
			)
			return &CheckResult{
				Name:    g.Name,
				Status:  "failed",
				Message: "target health JSON parse error",
				Details: details,
			}
		}

		var unhealthy []string
		for _, th := range thOutput.TargetHealthDescriptions {
			if th.TargetHealth.State != "healthy" {
				unhealthy = append(unhealthy,
					fmt.Sprintf("target %s:%d state=%s reason=%s (%s)",
						th.Target.Id, th.Target.Port,
						th.TargetHealth.State, th.TargetHealth.Reason, th.TargetHealth.Description))
			}
		}

		if len(unhealthy) > 0 {
			details = append(details,
				fmt.Sprintf("Unhealthy targets in target group %s:", tg.TargetGroupArn))
			details = append(details, unhealthy...)
			details = append(details,
				"Run: check security groups and NodePort service",
				fmt.Sprintf("Run: aws elbv2 describe-target-health --target-group-arn %s --region %s", tg.TargetGroupArn, region),
			)
			return &CheckResult{
				Name:    g.Name,
				Status:  "failed",
				Message: fmt.Sprintf("%d unhealthy NLB targets", len(unhealthy)),
				Details: details,
			}
		}
	}

	return nil
}

// --- helpers ---

func conditionTrue(conditions []k8sCondition, condType string) bool {
	for _, c := range conditions {
		if c.Type == condType {
			return strings.EqualFold(c.Status, "True")
		}
	}
	return false
}

func conditionMessage(conditions []k8sCondition, condType string) string {
	for _, c := range conditions {
		if c.Type == condType {
			return c.Message
		}
	}
	return "(condition not found)"
}

func conditionReason(conditions []k8sCondition, condType string) string {
	for _, c := range conditions {
		if c.Type == condType {
			return c.Reason
		}
	}
	return "(condition not found)"
}

func formatConditions(conditions []k8sCondition) string {
	var parts []string
	for _, c := range conditions {
		parts = append(parts, fmt.Sprintf("%s=%s (reason=%s, message=%s)", c.Type, c.Status, c.Reason, c.Message))
	}
	if len(parts) == 0 {
		return "(no conditions)"
	}
	return strings.Join(parts, "; ")
}

func truncate(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	return s[:maxLen] + "..."
}
