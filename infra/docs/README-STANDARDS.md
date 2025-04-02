# README Documentation Standards

This document outlines the standards for README files in both Terraform modules and Terragrunt configurations.

## General Guidelines

- All README files should be written in Markdown format
- Use consistent heading levels (# for title, ## for main sections, ### for subsections)
- Include code examples in fenced code blocks with appropriate language tags (```hcl for Terraform/Terragrunt)
- Maintain a clean, consistent format across all documentation
- Ensure all tables have proper headers and column alignment
- Use relative links when referencing other files in the repository

## Terraform Module READMEs

Each Terraform module should include a README.md file with the following sections:

1. **Title**: Module name
2. **Overview**: Brief description of the module's purpose
3. **Features**: Bullet list of key features
4. **Usage**: Code example showing typical usage
5. **Examples**: Basic and advanced usage examples
6. **Requirements**: Terraform and provider version requirements
7. **Providers**: Provider dependencies and versions
8. **Required Inputs**: Table of required input variables
9. **Optional Inputs**: Table of optional input variables
10. **Outputs**: Table of module outputs
11. **Validation Rules**: List of input validation rules
12. **Dependencies**: Other modules this module depends on
13. **Module Resources**: Resources created by the module
14. **Notes**: Important notes and best practices
15. **License**: License information

### Template

See the [MODULE-README-TEMPLATE.md](README-TEMPLATES/MODULE-README-TEMPLATE.md) for the standardized template.

## Terragrunt Configuration READMEs

Each Terragrunt configuration directory should include a README.md file with the following sections:

1. **Title**: Resource name, region, and environment
2. **Overview**: Brief description of what the configuration deploys
3. **Configuration Details**:
   - **Purpose**: Bullet list of key purposes
   - **Dependencies**: List of dependencies with descriptions
   - **Key Configuration Settings**: Important configuration values
4. **Usage**: Instructions for applying the configuration
5. **Dependencies on this Configuration**: List of configurations that depend on this one
6. **Implementation Notes**: Additional notes about the implementation

### Template

See the [TERRAGRUNT-README-TEMPLATE.md](README-TEMPLATES/TERRAGRUNT-README-TEMPLATE.md) for the standardized template.

## Updating READMEs

When updating READMEs, ensure the following:

1. Update all sections that are affected by code changes
2. Ensure examples remain accurate and functional
3. Update version requirements if module dependencies change
4. Keep lists of dependencies current
5. Add any new inputs, outputs, or resources
6. Document any important changes to the module behavior

## Review Checklist

Use this checklist when reviewing README files:

- [ ] Title is descriptive and follows the standard format
- [ ] Overview clearly explains the purpose
- [ ] Features list is comprehensive and accurate
- [ ] Usage examples are correct and follow best practices
- [ ] All required and optional inputs are documented
- [ ] All outputs are documented
- [ ] Validation rules are documented
- [ ] Dependencies are clearly listed
- [ ] Implementation notes include relevant information
- [ ] Format is consistent with other READMEs 