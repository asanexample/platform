package cost_monitoring_test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

// Plan-only tests: Budgets / Cost Anomaly Detection / Chatbot are payer-account
// billing resources that can't be safely apply/destroyed in CI. They require AWS
// credentials (the module reads aws_caller_identity), like the other AWS module
// tests here.

func TestCostMonitoring_Disabled(t *testing.T) {
	t.Parallel()

	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create": false,
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	assert.Empty(t, planStruct.ResourcePlannedValuesMap,
		"create=false should produce zero resources")
}

func TestCostMonitoring_Plan(t *testing.T) {
	t.Parallel()

	uniqueID := random.UniqueId()
	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":       true,
		"alert_emails": []string{"cost@example.com"},
		"budgets": map[string]interface{}{
			"consolidated": map[string]interface{}{"limit_usd": 2000},
			"platform":     map[string]interface{}{"limit_usd": 800, "linked_accounts": []string{"111122223333"}},
		},
		// slack_team_id left empty → Chatbot delivery disabled.
		"tags": map[string]string{"TestRun": uniqueID},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	expectedResources := []string{
		"module.cost_monitoring.aws_sns_topic.cost_alerts[0]",
		"module.cost_monitoring.aws_sns_topic_policy.cost_alerts[0]",
		`module.cost_monitoring.aws_sns_topic_subscription.email["cost@example.com"]`,
		`module.cost_monitoring.aws_budgets_budget.this["consolidated"]`,
		`module.cost_monitoring.aws_budgets_budget.this["platform"]`,
		"module.cost_monitoring.aws_ce_anomaly_monitor.services[0]",
		"module.cost_monitoring.aws_ce_anomaly_subscription.this[0]",
	}
	for _, resource := range expectedResources {
		assert.Contains(t, planStruct.ResourcePlannedValuesMap, resource,
			"plan should include %s", resource)
	}

	// Chatbot is gated off when slack_team_id is empty.
	assert.NotContains(t, planStruct.ResourcePlannedValuesMap,
		"module.cost_monitoring.aws_chatbot_slack_channel_configuration.cost[0]",
		"Chatbot config should be absent without slack_team_id")
	assert.NotContains(t, planStruct.ResourcePlannedValuesMap,
		"module.cost_monitoring.aws_iam_role.chatbot[0]",
		"Chatbot role should be absent without slack_team_id")
}

func TestCostMonitoring_ExistingMonitor(t *testing.T) {
	t.Parallel()

	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":               true,
		"existing_monitor_arn": "arn:aws:ce::111122223333:anomalymonitor/00000000-0000-0000-0000-000000000000",
		"budgets": map[string]interface{}{
			"consolidated": map[string]interface{}{"limit_usd": 2000},
		},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	// With an existing monitor ARN, the module subscribes to it and does NOT create a monitor.
	assert.NotContains(t, planStruct.ResourcePlannedValuesMap,
		"module.cost_monitoring.aws_ce_anomaly_monitor.services[0]",
		"should not create a monitor when existing_monitor_arn is set")
	assert.Contains(t, planStruct.ResourcePlannedValuesMap,
		"module.cost_monitoring.aws_ce_anomaly_subscription.this[0]",
		"should still create the anomaly subscription")
}

func TestCostMonitoring_WithSlack(t *testing.T) {
	t.Parallel()

	tmpDir := copyFixtureToTemp(t)

	vars := map[string]interface{}{
		"create":           true,
		"slack_team_id":    "T0000000000",
		"slack_channel_id": "C0000000000",
		"budgets": map[string]interface{}{
			"consolidated": map[string]interface{}{"limit_usd": 2000},
		},
	}

	opts := newTerraformOptions(t, tmpDir, vars)
	opts.PlanFilePath = tmpDir + "/plan.out"
	planStruct := terraform.InitAndPlanAndShowWithStruct(t, opts)

	expectedResources := []string{
		"module.cost_monitoring.aws_iam_role.chatbot[0]",
		"module.cost_monitoring.aws_chatbot_slack_channel_configuration.cost[0]",
	}
	for _, resource := range expectedResources {
		assert.Contains(t, planStruct.ResourcePlannedValuesMap, resource,
			"plan should include %s when slack_team_id is set", resource)
	}
}
