// Package cloud abstracts provider-specific API calls used by hooks.
// Implementations are registered per provider; the engine selects the right
// client based on unit.Provider.
package cloud

import (
	"context"
)

// Client abstracts provider-specific API calls used by hooks and validation.
type Client interface {
	SecretExists(ctx context.Context, secretID string, auth map[string]string) (bool, error)
}

// AWSClient extends Client with AWS-specific operations.
type AWSClient interface {
	Client
	DescribeEKSENIs(ctx context.Context, clusterName string, auth map[string]string) ([]string, error)
	ForceDeleteSecret(ctx context.Context, secretID string, auth map[string]string) error
}
