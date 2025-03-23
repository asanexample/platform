# Tests for Container Insights DCR Module

This directory contains tests for the Container Insights Data Collection Rules (DCR) module.

## Test Strategy

The testing strategy for this module includes:

1. **Integration Tests**: Verify that the module correctly creates the Azure Monitor Data Collection Rule and association.
2. **Validation Tests**: Ensure that input variables are correctly validated and error messages are clear.

## Test Cases

- Validate that the DCR name follows naming standards
- Validate that the DCR association is created correctly
- Validate error handling for invalid inputs

## Running Tests

Tests are automatically run as part of the CI pipeline.
