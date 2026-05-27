// Package engine provides the DAG-based orchestration engine for platctl.
package engine

import (
	"fmt"
	"sort"
)

// Action represents an infrastructure operation.
type Action int

const (
	// Apply creates or updates infrastructure.
	Apply Action = iota
	// Destroy tears down infrastructure.
	Destroy
)

// String returns the action name as used in terragrunt commands.
func (a Action) String() string {
	switch a {
	case Apply:
		return "apply"
	case Destroy:
		return "destroy"
	default:
		return "unknown"
	}
}

// Unit represents a single Terragrunt deployment unit.
type Unit struct {
	Name      string            // Qualified name: "platform/eks", "preprod/networking"
	Path      string            // Absolute path to the unit directory
	Env       string            // Environment name from config (e.g., "platform", "preprod")
	Provider  string            // Cloud provider: "aws", "azure", etc.
	DependsOn []string          // Qualified names of units this unit depends on
	Auth      map[string]string // Provider-specific credentials (e.g., {"profile": "management"})
}

// Graph holds units and their dependency relationships.
type Graph struct {
	units map[string]*Unit
}

// NewGraph creates a Graph from a slice of units.
// Returns an error if any unit references a dependency that doesn't exist in the graph.
func NewGraph(units []*Unit) (*Graph, error) {
	g := &Graph{units: make(map[string]*Unit, len(units))}
	for _, u := range units {
		if _, exists := g.units[u.Name]; exists {
			return nil, fmt.Errorf("duplicate unit %q", u.Name)
		}
		g.units[u.Name] = u
	}
	for _, u := range units {
		for _, dep := range u.DependsOn {
			if _, exists := g.units[dep]; !exists {
				return nil, fmt.Errorf("unit %q depends on %q, which does not exist", u.Name, dep)
			}
		}
	}
	return g, nil
}

// Units returns all units in the graph, sorted by name for deterministic output.
func (g *Graph) Units() []*Unit {
	result := make([]*Unit, 0, len(g.units))
	for _, u := range g.units {
		result = append(result, u)
	}
	sort.Slice(result, func(i, j int) bool {
		return result[i].Name < result[j].Name
	})
	return result
}

// Unit returns a single unit by name, or nil if not found.
func (g *Graph) Unit(name string) *Unit {
	return g.units[name]
}

// Len returns the number of units in the graph.
func (g *Graph) Len() int {
	return len(g.units)
}

// FilterByEnv returns a new graph containing only units from the specified environment.
// Cross-env dependencies pointing outside the filtered set are removed.
func (g *Graph) FilterByEnv(env string) (*Graph, error) {
	var filtered []*Unit
	for _, u := range g.units {
		if u.Env != env {
			continue
		}
		cp := *u
		cp.DependsOn = filterDeps(u.DependsOn, func(dep string) bool {
			if d, ok := g.units[dep]; ok {
				return d.Env == env
			}
			return false
		})
		filtered = append(filtered, &cp)
	}
	return NewGraph(filtered)
}

// Reverse returns a new graph with all dependency edges reversed.
// Used for teardown: dependents become dependencies so leaf nodes are destroyed first.
func (g *Graph) Reverse() (*Graph, error) {
	reverse := make(map[string][]string)
	for name := range g.units {
		reverse[name] = nil
	}
	for _, u := range g.units {
		for _, dep := range u.DependsOn {
			reverse[dep] = append(reverse[dep], u.Name)
		}
	}
	var units []*Unit
	for _, u := range g.units {
		cp := *u
		cp.DependsOn = reverse[u.Name]
		units = append(units, &cp)
	}
	return NewGraph(units)
}

// TopoSort returns units in a valid topological order (dependencies before dependents).
// Returns an error if the graph contains a cycle.
func (g *Graph) TopoSort() ([]*Unit, error) {
	inDegree := make(map[string]int, len(g.units))
	for name := range g.units {
		inDegree[name] = 0
	}
	for _, u := range g.units {
		for _, dep := range u.DependsOn {
			_ = dep
		}
	}
	// Count incoming edges
	for _, u := range g.units {
		inDegree[u.Name] += 0 // ensure entry exists
		for _, dep := range u.DependsOn {
			_ = dep
		}
	}
	dependents := make(map[string][]string)
	for _, u := range g.units {
		for _, dep := range u.DependsOn {
			dependents[dep] = append(dependents[dep], u.Name)
			inDegree[u.Name]++
		}
	}

	// Seed queue with zero-dependency units (sorted for determinism)
	var queue []string
	for name, deg := range inDegree {
		if deg == 0 {
			queue = append(queue, name)
		}
	}
	sort.Strings(queue)

	var order []*Unit
	for len(queue) > 0 {
		name := queue[0]
		queue = queue[1:]
		order = append(order, g.units[name])

		// Collect and sort newly ready dependents for deterministic ordering
		var ready []string
		for _, dep := range dependents[name] {
			inDegree[dep]--
			if inDegree[dep] == 0 {
				ready = append(ready, dep)
			}
		}
		sort.Strings(ready)
		queue = append(queue, ready...)
	}

	if len(order) != len(g.units) {
		return nil, fmt.Errorf("dependency cycle detected: processed %d of %d units", len(order), len(g.units))
	}
	return order, nil
}

// Waves returns units grouped by parallel execution wave.
// Units within the same wave have no dependency on each other and can run concurrently.
func (g *Graph) Waves() ([][]* Unit, error) {
	inDegree := make(map[string]int, len(g.units))
	dependents := make(map[string][]string)
	for name := range g.units {
		inDegree[name] = 0
	}
	for _, u := range g.units {
		for _, dep := range u.DependsOn {
			dependents[dep] = append(dependents[dep], u.Name)
			inDegree[u.Name]++
		}
	}

	var waves [][]*Unit
	var queue []string
	for name, deg := range inDegree {
		if deg == 0 {
			queue = append(queue, name)
		}
	}
	sort.Strings(queue)

	for len(queue) > 0 {
		wave := make([]*Unit, 0, len(queue))
		for _, name := range queue {
			wave = append(wave, g.units[name])
		}
		waves = append(waves, wave)

		var next []string
		for _, name := range queue {
			for _, dep := range dependents[name] {
				inDegree[dep]--
				if inDegree[dep] == 0 {
					next = append(next, dep)
				}
			}
		}
		sort.Strings(next)
		queue = next
	}

	total := 0
	for _, w := range waves {
		total += len(w)
	}
	if total != len(g.units) {
		return nil, fmt.Errorf("dependency cycle detected: processed %d of %d units", total, len(g.units))
	}
	return waves, nil
}

// Dependents returns the transitive set of units that depend on the given unit.
// Useful for determining which units to skip when a unit fails.
func (g *Graph) Dependents(name string) []string {
	dependents := make(map[string][]string)
	for _, u := range g.units {
		for _, dep := range u.DependsOn {
			dependents[dep] = append(dependents[dep], u.Name)
		}
	}

	visited := make(map[string]bool)
	var walk func(string)
	walk = func(n string) {
		for _, dep := range dependents[n] {
			if !visited[dep] {
				visited[dep] = true
				walk(dep)
			}
		}
	}
	walk(name)

	result := make([]string, 0, len(visited))
	for dep := range visited {
		result = append(result, dep)
	}
	sort.Strings(result)
	return result
}

func filterDeps(deps []string, keep func(string) bool) []string {
	var result []string
	for _, d := range deps {
		if keep(d) {
			result = append(result, d)
		}
	}
	return result
}
