#!/bin/bash

# Script to validate and update documentation

set -e

# Variables
DOCS_DIR="infra/docs"
DIAGRAM_DIR="$DOCS_DIR/diagrams"
TOC_FILE="$DOCS_DIR/README.md"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

echo "VIP Platform Documentation Validator"
echo "===================================="
echo ""

# Check if docs directory exists
if [ ! -d "$DOCS_DIR" ]; then
  echo -e "${RED}Error: Documentation directory $DOCS_DIR not found${NC}"
  exit 1
fi

# Check for missing documents listed in the table of contents
echo "Checking for missing documents..."
missing_files=0
for file in $(grep -o '\[.*\]([^)]*)' "$TOC_FILE" | grep -v 'Coming Soon' | grep -o '([^)]*)' | tr -d '()'); do
  if [[ "$file" != "http"* && "$file" != "diagrams/"* && ! -f "$DOCS_DIR/$file" ]]; then
    echo -e "${YELLOW}Missing file: $DOCS_DIR/$file${NC}"
    missing_files=$((missing_files+1))
  fi
done

if [ $missing_files -eq 0 ]; then
  echo -e "${GREEN}All documents listed in the table of contents exist.${NC}"
else
  echo -e "${YELLOW}Found $missing_files missing files listed in the table of contents.${NC}"
fi
echo ""

# Check for broken links within documents
echo "Checking for broken internal links..."
broken_links=0
for file in "$DOCS_DIR"/*.md; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    for link in $(grep -o '\[.*\]([^)]*)' "$file" | grep -o '([^)]*)' | tr -d '()'); do
      if [[ "$link" != "http"* && "$link" != "diagrams/"* && "$link" != "#"* && ! -f "$DOCS_DIR/$link" ]]; then
        echo -e "${YELLOW}Broken link in $filename: $link${NC}"
        broken_links=$((broken_links+1))
      fi
    done
  fi
done

if [ $broken_links -eq 0 ]; then
  echo -e "${GREEN}No broken internal links found.${NC}"
else
  echo -e "${YELLOW}Found $broken_links broken internal links.${NC}"
fi
echo ""

# Check for missing diagrams
echo "Checking for referenced diagrams..."
missing_diagrams=0
for file in "$DOCS_DIR"/*.md; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    for diagram in $(grep -o '!\[.*\](diagrams/[^)]*)' "$file" | grep -o '(diagrams/[^)]*)' | tr -d '()'); do
      if [ ! -f "$DOCS_DIR/$diagram" ]; then
        echo -e "${YELLOW}Missing diagram in $filename: $diagram${NC}"
        missing_diagrams=$((missing_diagrams+1))
      fi
    done
  fi
done

if [ $missing_diagrams -eq 0 ]; then
  echo -e "${GREEN}All referenced diagrams exist.${NC}"
else
  echo -e "${YELLOW}Found $missing_diagrams missing referenced diagrams.${NC}"
fi
echo ""

# List documents not referenced in the table of contents
echo "Checking for unlisted documents..."
unlisted_docs=0
for file in "$DOCS_DIR"/*.md; do
  if [ -f "$file" ] && [ "$(basename "$file")" != "README.md" ]; then
    filename=$(basename "$file")
    if ! grep -q "$filename" "$TOC_FILE"; then
      echo -e "${YELLOW}Document not listed in table of contents: $filename${NC}"
      unlisted_docs=$((unlisted_docs+1))
    fi
  fi
done

if [ $unlisted_docs -eq 0 ]; then
  echo -e "${GREEN}All documents are listed in the table of contents.${NC}"
else
  echo -e "${YELLOW}Found $unlisted_docs documents not listed in the table of contents.${NC}"
fi
echo ""

# List all documents with placeholders
echo "Documents with placeholders:"
placeholder_docs=0
for file in "$DOCS_DIR"/*.md; do
  if [ -f "$file" ]; then
    filename=$(basename "$file")
    if grep -q "This document is under development" "$file" || grep -q "will be provided in a future update" "$file"; then
      echo -e "${YELLOW}Document with placeholders: $filename${NC}"
      placeholder_docs=$((placeholder_docs+1))
    fi
  fi
done

if [ $placeholder_docs -eq 0 ]; then
  echo -e "${GREEN}No documents with placeholders found.${NC}"
else
  echo -e "${YELLOW}Found $placeholder_docs documents with placeholders.${NC}"
fi
echo ""

# Summary
echo "Documentation Summary:"
echo "======================"
echo -e "Total documents: $(ls "$DOCS_DIR"/*.md | wc -l | tr -d ' ')"
echo -e "Missing files: ${YELLOW}$missing_files${NC}"
echo -e "Broken links: ${YELLOW}$broken_links${NC}"
echo -e "Missing diagrams: ${YELLOW}$missing_diagrams${NC}"
echo -e "Unlisted documents: ${YELLOW}$unlisted_docs${NC}"
echo -e "Documents with placeholders: ${YELLOW}$placeholder_docs${NC}"
echo ""

if [ $missing_files -eq 0 ] && [ $broken_links -eq 0 ] && [ $missing_diagrams -eq 0 ] && [ $unlisted_docs -eq 0 ]; then
  echo -e "${GREEN}Documentation structure is valid.${NC}"
else
  echo -e "${YELLOW}Documentation needs attention. Please fix the issues above.${NC}"
fi 