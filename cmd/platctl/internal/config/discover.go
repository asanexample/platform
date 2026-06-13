package config

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/hashicorp/hcl/v2"
	"github.com/hashicorp/hcl/v2/hclsyntax"

	"github.com/asanexample/platform/cmd/platctl/internal/engine"
)

// Discover scans the configured environment directories for Terragrunt units,
// parses their dependency blocks, and builds a complete dependency graph.
func Discover(cfg *Config, repoRoot string) (*engine.Graph, error) {
	envPaths := make(map[string]string, len(cfg.Environments))
	for name, env := range cfg.Environments {
		envPaths[name] = filepath.Join(repoRoot, env.Path)
	}

	var units []*engine.Unit
	for envName, envCfg := range cfg.Environments {
		envDir := filepath.Join(repoRoot, envCfg.Path)

		discovered, err := discoverUnits(envName, envDir, envCfg, cfg, envPaths, repoRoot)
		if err != nil {
			return nil, fmt.Errorf("discovering units in %s: %w", envName, err)
		}
		units = append(units, discovered...)
	}

	return engine.NewGraph(units)
}

// discoverUnits finds all Terragrunt units in a single environment directory.
func discoverUnits(envName, envDir string, envCfg EnvConfig, cfg *Config, envPaths map[string]string, repoRoot string) ([]*engine.Unit, error) {
	entries, err := os.ReadDir(envDir)
	if err != nil {
		return nil, fmt.Errorf("reading directory %s: %w", envDir, err)
	}

	var units []*engine.Unit
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}
		unitDir := filepath.Join(envDir, entry.Name())
		hclPath := filepath.Join(unitDir, "terragrunt.hcl")
		if _, err := os.Stat(hclPath); os.IsNotExist(err) {
			continue
		}

		unitName := entry.Name()
		qualifiedName := envName + "/" + unitName

		deps, err := parseDependencies(hclPath, unitDir, envPaths, envName)
		if err != nil {
			return nil, fmt.Errorf("parsing dependencies for %s: %w", qualifiedName, err)
		}

		// Merge implicit deps from config overrides
		if override, ok := cfg.Overrides[qualifiedName]; ok {
			deps = append(deps, override.ImplicitDeps...)
		}

		// Deduplicate and sort
		deps = dedup(deps)

		unit := &engine.Unit{
			Name:      qualifiedName,
			Path:      unitDir,
			Env:       envName,
			Provider:  envCfg.Provider,
			DependsOn: deps,
			Auth:      cfg.AuthForUnit(envName, unitName),
		}
		units = append(units, unit)
	}

	return units, nil
}

// parseDependencies extracts dependency block config_path values from a terragrunt.hcl file
// and resolves them to qualified unit names.
func parseDependencies(hclPath, unitDir string, envPaths map[string]string, currentEnv string) ([]string, error) {
	src, err := os.ReadFile(hclPath)
	if err != nil {
		return nil, fmt.Errorf("reading %s: %w", hclPath, err)
	}

	file, diags := hclsyntax.ParseConfig(src, hclPath, hcl.Pos{Line: 1, Column: 1})
	if diags.HasErrors() {
		return nil, fmt.Errorf("parsing HCL %s: %s", hclPath, diags.Error())
	}

	body, ok := file.Body.(*hclsyntax.Body)
	if !ok {
		return nil, fmt.Errorf("unexpected HCL body type in %s", hclPath)
	}

	var deps []string
	for _, block := range body.Blocks {
		if block.Type != "dependency" {
			continue
		}

		configPath, err := extractConfigPath(block)
		if err != nil {
			continue // skip dependencies without a parseable config_path
		}

		resolved, err := resolveDepPath(configPath, unitDir, envPaths, currentEnv)
		if err != nil {
			continue // skip unresolvable paths (may reference envs not in config)
		}
		deps = append(deps, resolved)
	}

	return deps, nil
}

// extractConfigPath pulls the config_path string from a dependency block.
func extractConfigPath(block *hclsyntax.Block) (string, error) {
	attr, ok := block.Body.Attributes["config_path"]
	if !ok {
		return "", fmt.Errorf("no config_path attribute")
	}

	// Evaluate the expression — config_path is always a string literal in our codebase
	val, diags := attr.Expr.Value(nil)
	if diags.HasErrors() {
		return "", fmt.Errorf("evaluating config_path: %s", diags.Error())
	}
	if val.Type().FriendlyName() != "string" {
		return "", fmt.Errorf("config_path is not a string")
	}

	return val.AsString(), nil
}

// resolveDepPath converts a relative config_path to a qualified unit name (e.g., "platform/eks").
//
// Same-env deps use simple relative paths like "../networking".
// Cross-env deps use longer paths like "../../../../preprod/us-east-1/platform/eks".
// We resolve the path to an absolute directory, then match it against known environment paths.
func resolveDepPath(configPath, unitDir string, envPaths map[string]string, currentEnv string) (string, error) {
	// Resolve to absolute path
	absPath := configPath
	if !filepath.IsAbs(configPath) {
		absPath = filepath.Join(unitDir, configPath)
	}
	absPath = filepath.Clean(absPath)

	// Try to match against each environment's base path
	for envName, envPath := range envPaths {
		cleanEnvPath := filepath.Clean(envPath)
		if strings.HasPrefix(absPath, cleanEnvPath+"/") {
			unitName := strings.TrimPrefix(absPath, cleanEnvPath+"/")
			// unitName might have nested path separators; take only the last component
			// (unit dirs are flat, not nested)
			unitName = filepath.Base(unitName)
			return envName + "/" + unitName, nil
		}
		if absPath == cleanEnvPath {
			continue // exact match on env dir itself, not a unit
		}
	}

	return "", fmt.Errorf("could not resolve %q to any known environment", configPath)
}

func dedup(ss []string) []string {
	if len(ss) == 0 {
		return nil
	}
	seen := make(map[string]bool, len(ss))
	var result []string
	for _, s := range ss {
		if !seen[s] {
			seen[s] = true
			result = append(result, s)
		}
	}
	sort.Strings(result)
	return result
}
