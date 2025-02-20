#!/bin/bash

# This script concatenates multiple .gitignore templates from GitHub into a single file.
# It fetches the raw content of each template and appends it to the output file.
# URLs can be provided via stdin, from a file, or default to hardcoded values.
# The output file name can also be specified, with a default of `.gitignore`.

# Usage:
#   cat urls.txt | scripts/concat_gitignores.sh
#   cat urls.txt | scripts/concat_gitignores.sh --output custom.output.gitignore
#   scripts/concat_gitignores.sh
#   scripts/concat_gitignores.sh --output custom.output.gitignore
#   scripts/concat_gitignores.sh urls.txt
#   scripts/concat_gitignores.sh urls.txt --output custom.output.gitignore

# Debugging flag
set -e  # Exit on errors

# Hardcoded URLs (used if no input is provided)
DEFAULT_URLS=(
  "https://github.com/github/gitignore/blob/main/Python.gitignore"
  "https://github.com/github/gitignore/blob/main/community/Python/JupyterNotebooks.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/VisualStudioCode.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/JetBrains.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Eclipse.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/SublimeText.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Linux.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/macOS.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Windows.gitignore"
  "https://github.com/github/gitignore/blob/main/Node.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Archives.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Backup.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Diff.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Patch.gitignore"
)

# Default output file
OUTPUT_FILE=".gitignore"

# Variables
INPUT_FILE=""
URLS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    *)
      if [[ -z "$INPUT_FILE" ]]; then
        INPUT_FILE="$1"
        shift
      else
        echo "Unknown argument: $1"
        echo "Usage: $0 [<input_file>] [--output <output_file>]"
        exit 1
      fi
      ;;
  esac
done

# Determine the source of URLs
if [[ -n "$INPUT_FILE" && -f "$INPUT_FILE" ]]; then
  # Read URLs from the provided file
  mapfile -t URLS < "$INPUT_FILE"
elif ! [ -t 0 ]; then
  # Read URLs from stdin if piped
  mapfile -t URLS
else
  # Use hardcoded URLs as default
  URLS=("${DEFAULT_URLS[@]}")
fi

# Calculate the length of the longest URL
MAX_URL_LENGTH=0
for url in "${URLS[@]}"; do
  if [[ ${#url} -gt $MAX_URL_LENGTH ]]; then
    MAX_URL_LENGTH=${#url}
  fi
done

# Create the comment header
HEADER_LENGTH=$((MAX_URL_LENGTH + 4))
HEADER=$(printf '#%.0s' $(seq 1 $HEADER_LENGTH))

{
  echo "$HEADER"
  echo "# This .gitignore is composed of the following templates (retrieved $(date +%Y-%m-%d)):"
  for url in "${URLS[@]}"; do
    echo "# - $url"
  done
  echo "$HEADER"
  echo ""
} > "$OUTPUT_FILE"

echo "Initialized output file with header: $OUTPUT_FILE"

# Loop through URLs
for url in "${URLS[@]}"; do
  echo "Processing URL: $url"

  # Extract the filename (e.g., Python.gitignore)
  FILENAME=$(basename "$url")

  # Calculate dynamic block length
  PREFACE_LENGTH=$(( ${#FILENAME} + 4 ))  # Length of " # FILENAME # "
  PREFACE=$(printf '#%.0s' $(seq 1 $PREFACE_LENGTH))

  # Preface block for this template
  {
    echo "$PREFACE"
    echo "# $FILENAME #"
    echo "$PREFACE"
    echo ""
  } >> "$OUTPUT_FILE"

  # Convert GitHub URL to raw content URL
  RAW_URL=$(echo "$url" | sed 's|github.com|raw.githubusercontent.com|; s|/blob||')
  echo "Converted to raw URL: $RAW_URL"

  # Fetch content
  CONTENT=$(curl -s "$RAW_URL" | awk '{ gsub(/\r$/, ""); gsub(/[ \t]+$/, ""); print }')
  if [[ -z "$CONTENT" ]]; then
    echo "Failed to fetch content from: $RAW_URL"
  else
    echo "Appending content from: $RAW_URL"
    echo "$CONTENT" >> "$OUTPUT_FILE"
    echo -e "\n# End of $url\n" >> "$OUTPUT_FILE"
  fi
done

# Normalize line endings in the final output file
tr -d '\r' < "$OUTPUT_FILE" > .temp_file && mv .temp_file "$OUTPUT_FILE"

# Ensure single trailing newline
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  sed -i ':a;/^$/{$d;N;ba;}' "$OUTPUT_FILE"  # spellchecker:disable-line
elif [[ "$OSTYPE" == "darwin"* ]]; then
  sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$OUTPUT_FILE"  # spellchecker:disable-line
else
  echo "Unknown OS: unable to ensure single trailing newline"
fi

echo "Combined .gitignore created as $OUTPUT_FILE"
