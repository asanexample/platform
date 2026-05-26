// Package cloud abstracts provider-specific API calls used by hooks.
// Implementations are registered per provider; the engine selects the right
// client based on unit.Provider.
package cloud

import (
	"context"
	"fmt"
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

// Checker validates that a deployed unit is healthy.
// Extension point for `platctl validate` — cloud-specific checks are a follow-up.
type Checker interface {
	Check(ctx context.Context, unitName string, auth map[string]string) error
}

// Registry maps provider names to their client implementations.
type Registry struct {
	clients map[string]Client
}

// NewRegistry creates an empty provider registry.
func NewRegistry() *Registry {
	return &Registry{clients: make(map[string]Client)}
}

// Register adds a client for the given provider.
func (r *Registry) Register(provider string, client Client) {
	r.clients[provider] = client
}

// Get returns the client for the given provider.
func (r *Registry) Get(provider string) (Client, error) {
	c, ok := r.clients[provider]
	if !ok {
		return nil, fmt.Errorf("no cloud client registered for provider %q", provider)
	}
	return c, nil
}
