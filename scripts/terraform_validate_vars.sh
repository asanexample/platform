#!/bin/bash
# Script to identify Terraform variables that might need validation

# Set the base directory
BASE_DIR="/Users/josh/centric/platform/infra/modules"
if [ "$1" != "" ]; then
  echo "Checking specific path: $1"
  BASE_DIR=$(dirname "$1")
  SPECIFIC_FILE=$(basename "$1")
fi

# Color codes for output
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Scanning Terraform modules for variables that might need validation...${NC}"
echo ""

# Find all variables.tf files
if [ -n "$SPECIFIC_FILE" ]; then
  VARS_FILES=$(find "$BASE_DIR" -name "$SPECIFIC_FILE")
else
  VARS_FILES=$(find $BASE_DIR -name "variables.tf")
fi

# Counter for variables that need attention
TOTAL_VARS=0
VALIDATED_VARS=0
MISSING_VALIDATION=0

for FILE in $VARS_FILES; do
  MODULE_NAME=$(dirname $FILE | sed "s|$BASE_DIR/||")
  echo -e "${BLUE}Checking module: ${YELLOW}$MODULE_NAME${NC}"
  
  # Extract variable blocks with improved parsing
  VAR_BLOCKS=$(awk '
    /^variable/ { 
      flag=1; 
      block=""; 
      level=0;
    } 
    flag { 
      block=block"\n"$0; 
      if ($0 ~ /{/) level++; 
      if ($0 ~ /}/) level--; 
      if (level==0) { 
        print block; 
        flag=0;
      } 
    }
  ' "$FILE")
  
  # Process each variable block
  while IFS= read -r VAR_BLOCK; do
    if [[ -z "$VAR_BLOCK" ]]; then
      continue
    fi
    
    # Extract variable name
    VAR_NAME=$(echo "$VAR_BLOCK" | grep "^variable" | sed -E 's/variable "([^"]+)".*/\1/')
    
    # Check if variable has validation - improved detection
    if echo "$VAR_BLOCK" | grep -q -E '(validation|^\s*validation\s*{)'; then
      ((VALIDATED_VARS++))
      continue
    fi
    
    # Extract variable type
    VAR_TYPE=$(echo "$VAR_BLOCK" | grep -E '^\s*type\s*=' | sed -E 's/.*type\s*=\s*([a-zA-Z0-9_]+).*/\1/')
    if [[ -z "$VAR_TYPE" ]]; then
      # Try for complex types
      if echo "$VAR_BLOCK" | grep -q "type\s*="; then
        VAR_TYPE="complex"
      else
        VAR_TYPE="unknown"
      fi
    fi
    
    # Check if variable has default value
    HAS_DEFAULT=0
    if echo "$VAR_BLOCK" | grep -q "default\s*="; then
      HAS_DEFAULT=1
    fi
    
    # Simple heuristic for variables that might need validation
    NEEDS_VALIDATION=0
    if [[ "$VAR_NAME" == *"name"* || "$VAR_NAME" == "location" || "$VAR_NAME" == *"id"* || 
          "$VAR_NAME" == *"cidr"* || "$VAR_NAME" == *"address"* || "$VAR_NAME" == *"sku"* || 
          "$VAR_NAME" == *"tier"* || "$VAR_NAME" == *"region"* || "$VAR_NAME" == *"zone"* || 
          "$VAR_NAME" == *"size"* || "$VAR_NAME" == *"count"* || "$VAR_NAME" == *"limit"* || 
          "$VAR_NAME" == *"retention"* || "$VAR_NAME" == *"prefix"* ]]; then
      NEEDS_VALIDATION=1
    fi
    
    if [[ "$NEEDS_VALIDATION" -eq 1 && "$VAR_TYPE" != "bool" ]]; then
      ((MISSING_VALIDATION++))
      echo -e "  ${RED}Missing validation:${NC} $VAR_NAME (type: $VAR_TYPE, has default: $([ $HAS_DEFAULT -eq 1 ] && echo "yes" || echo "no"))"
    fi
    
    ((TOTAL_VARS++))
  done <<< "$VAR_BLOCKS"
  
  echo ""
done

echo -e "${BLUE}Summary:${NC}"
echo -e "  Total variables examined: ${TOTAL_VARS}"
echo -e "  Variables with validation: ${GREEN}${VALIDATED_VARS}${NC}"
echo -e "  Variables likely needing validation: ${RED}${MISSING_VALIDATION}${NC}"
if [ $TOTAL_VARS -gt 0 ]; then
  echo -e "  Validation coverage: ${YELLOW}$(( (VALIDATED_VARS * 100) / (TOTAL_VARS) ))%${NC}"
else
  echo -e "  Validation coverage: ${YELLOW}0%${NC}"
fi

echo ""
echo -e "${BLUE}Recommendations:${NC}"
echo -e "  1. Review the variables highlighted above and add appropriate validation."
echo -e "  2. Refer to the validation standards document at: docs/terraform/variable_validation_standards.md"
echo -e "  3. Focus on variables with resource names, locations, network addresses, and numeric limits first." 