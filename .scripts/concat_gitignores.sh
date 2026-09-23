#!/usr/bin/env bash

set -euo pipefail

SCRIPT_NAME=$(basename "$0")

usage() {
  cat << EOF
Usage: $SCRIPT_NAME [--output <output_file>] [--] [<input_file>]

Concatenate multiple .gitignore templates into a single file by fetching
template URLs from a file, stdin, or built-in defaults. If <input_file> is
given, the URLs are read from it, one per line. Otherwise, if stdin is not a
terminal, the URLs are read from stdin, one per line. Otherwise, a built-in
list of template URLs is used. Lines of the file or of stdin that are empty or
contain only whitespace are ignored.

A failed fetch does not stop the run, so every failed fetch is reported. The
output file is written only if every template is fetched. If any fetch fails,
the output file is left unchanged and the exit status is 1.

Arguments:
  <input_file>            Optional file containing one URL per line.

Options:
  --output <output_file>  Destination file name. Defaults to .gitignore.
  --                      Treat the next argument as the input file, even if
                          it begins with a dash.
  -h, --help              Show this help message and exit.

Examples:
  cat urls.txt | $SCRIPT_NAME
  cat urls.txt | $SCRIPT_NAME --output custom.output.gitignore
  $SCRIPT_NAME
  $SCRIPT_NAME urls.txt
  $SCRIPT_NAME urls.txt --output custom.output.gitignore
  $SCRIPT_NAME -- -urls.txt
EOF
}

# Append each line of stdin that is not blank to URLS.
read_urls() {
  local line
  # read fails at the end of input even when it has read a last line that has
  # no trailing newline, so a nonempty line is kept regardless.
  while IFS= read -r line || [[ -n $line ]]; do
    # A blank line, such as a separator or an extra newline at the end of the
    # input, names no template. Kept as a URL, it would be counted as a failed
    # fetch and would stop the output file from being written.
    [[ $line == *[![:space:]]* ]] || continue
    URLS+=("$line")
  done
}

DEFAULT_URLS=(
  # Language / runtime / ecosystem
  "https://github.com/github/gitignore/blob/main/Node.gitignore"

  # IDEs / editors
  "https://github.com/github/gitignore/blob/main/Global/Cursor.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Eclipse.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Emacs.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/JetBrains.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/SublimeText.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Vim.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/VisualStudioCode.gitignore"
  "https://github.com/github/gitignore/blob/main/VisualStudio.gitignore"

  # OS / platform
  "https://github.com/github/gitignore/blob/main/Global/Linux.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/macOS.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Windows.gitignore"

  # Tools / documents / misc artifacts
  "https://github.com/github/gitignore/blob/main/Global/Archives.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Backup.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Diff.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/MicrosoftOffice.gitignore"
  "https://github.com/github/gitignore/blob/main/Global/Patch.gitignore"
)

OUTPUT_FILE=".gitignore"

# Variables
POSITIONAL=()
URLS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      if [[ -z ${2:-} ]]; then
        echo "Error: --output requires a file name." >&2
        usage >&2
        exit 2
      fi
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --)
      shift
      POSITIONAL+=("$@")
      break
      ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      usage >&2
      exit 2
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL[@]} -gt 1 ]]; then
  echo "Error: Multiple input files specified: '${POSITIONAL[0]}' and '${POSITIONAL[1]}'" >&2
  usage >&2
  exit 2
fi

if ! command -v curl > /dev/null 2>&1; then
  echo "Error: 'curl' is required but not installed." >&2
  echo "Install it from: https://curl.se/download.html" >&2
  exit 1
fi

# The finished file is moved into place with mv, which would put it inside a
# directory instead of replacing it, and which, with -f, replaces a read-only
# file that a redirection would refuse to write. mv also fails if it cannot
# write to the directory that holds the output file. These checks stop the run
# before any template is fetched.
if [[ -d $OUTPUT_FILE ]]; then
  echo "Error: Output file '$OUTPUT_FILE' is a directory." >&2
  exit 1
fi
if [[ -e $OUTPUT_FILE && ! -w $OUTPUT_FILE ]]; then
  echo "Error: Output file '$OUTPUT_FILE' is not writable." >&2
  exit 1
fi
OUTPUT_DIR=.
if [[ $OUTPUT_FILE == */* ]]; then
  OUTPUT_DIR=${OUTPUT_FILE%/*}
  # For a path directly under the root directory, such as /x, the removal of
  # the last component leaves an empty string.
  OUTPUT_DIR=${OUTPUT_DIR:-/}
fi
if [[ ! -d $OUTPUT_DIR || ! -w $OUTPUT_DIR ]]; then
  echo "Error: Directory '$OUTPUT_DIR' of output file '$OUTPUT_FILE' does not exist or is not writable." >&2
  exit 1
fi

# Determine the source of URLs
if [[ ${#POSITIONAL[@]} -eq 1 ]]; then
  INPUT_FILE=${POSITIONAL[0]}
  if [[ ! -r $INPUT_FILE || -d $INPUT_FILE ]]; then
    echo "Error: Cannot read input file '$INPUT_FILE'." >&2
    exit 1
  fi
  read_urls < "$INPUT_FILE"
elif ! [ -t 0 ]; then
  read_urls
else
  URLS=("${DEFAULT_URLS[@]}")
fi

# Calculate the length of the longest URL
MAX_URL_LENGTH=0
for URL in ${URLS[@]+"${URLS[@]}"}; do
  if [[ ${#URL} -gt $MAX_URL_LENGTH ]]; then
    MAX_URL_LENGTH=${#URL}
  fi
done

# Build the output in a temporary directory and move it into place only when
# it is complete, so that an interrupted run leaves no partial output file.
# Files are created in a directory rather than by mktemp itself because mktemp
# creates files with mode 0600, while a file created by redirection gets the
# mode that the umask allows.
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
BUILD_FILE="$TMP_DIR/build"
NORMALIZED_FILE="$TMP_DIR/normalized"

# Create the comment header
HEADER_LENGTH=$((MAX_URL_LENGTH + 4))
HEADER=$(printf '#%.0s' $(seq 1 "$HEADER_LENGTH"))

{
  echo "$HEADER"
  echo "# This .gitignore is composed of the following templates (retrieved $(date +%Y-%m-%d)):"
  for URL in ${URLS[@]+"${URLS[@]}"}; do
    echo "# - $URL"
  done
  echo "$HEADER"
  echo ""
} > "$BUILD_FILE"

echo "Building output file: $OUTPUT_FILE"

FAILED_FETCHES=0

# Loop through URLs
for URL in ${URLS[@]+"${URLS[@]}"}; do
  echo "Processing URL: $URL"

  # Extract the filename (e.g., Python.gitignore)
  FILENAME=$(basename "$URL")

  # Calculate dynamic block length
  PREFACE_LENGTH=$((${#FILENAME} + 4)) # Length of " # FILENAME # "
  PREFACE=$(printf '#%.0s' $(seq 1 "$PREFACE_LENGTH"))

  # Preface block for this template
  {
    echo "$PREFACE"
    echo "# $FILENAME #"
    echo "$PREFACE"
    echo ""
  } >> "$BUILD_FILE"

  # Convert GitHub URL to raw content URL
  RAW_URL=$(echo "$URL" | sed 's|github.com|raw.githubusercontent.com|; s|/blob||')
  echo "Converted to raw URL: $RAW_URL"

  # Without -f, curl exits 0 on an HTTP error status, such as 404, and prints
  # the error page as if it were template content. With -f, curl fails on an
  # HTTP error as it does on a network error, and under pipefail the failure
  # makes this assignment fail. The assignment is the condition of the if
  # statement, where set -e does not apply, so that a failed fetch does not end
  # the run and one run reports every failed fetch. Testing the exit status
  # rather than whether the content is empty keeps an empty template, which was
  # fetched successfully, from being counted as a failed fetch.
  if ! CONTENT=$(curl -fsSL "$RAW_URL" | awk '{ gsub(/\r$/, ""); gsub(/[ \t]+$/, ""); print }'); then
    echo "Error: Failed to fetch $RAW_URL" >&2
    FAILED_FETCHES=$((FAILED_FETCHES + 1))
  elif [[ -z $CONTENT ]]; then
    echo "Warning: Template $RAW_URL is empty." >&2
  else
    echo "Appending content from: $RAW_URL"
    echo "$CONTENT" >> "$BUILD_FILE"
    echo -e "\n# End of $URL\n" >> "$BUILD_FILE"
  fi
done

if [[ $FAILED_FETCHES -gt 0 ]]; then
  echo "Error: $FAILED_FETCHES of ${#URLS[@]} template fetches failed; output file '$OUTPUT_FILE' was not changed." >&2
  exit 1
fi

# Normalize line endings in the built output
tr -d '\r' < "$BUILD_FILE" > "$NORMALIZED_FILE"

# Ensure single trailing newline
if [[ $OSTYPE == "linux-gnu"* ]]; then
  sed -i ':a;/^$/{$d;N;ba;}' "$NORMALIZED_FILE" # spellchecker:disable-line
elif [[ $OSTYPE == "darwin"* ]]; then
  sed -i '' -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$NORMALIZED_FILE" # spellchecker:disable-line
else
  echo "Warning: Unknown OS '$OSTYPE'; unable to ensure a single trailing newline." >&2
fi

echo -e "!.gitkeep" >> "$NORMALIZED_FILE"

if ! mv -f -- "$NORMALIZED_FILE" "$OUTPUT_FILE"; then
  echo "Error: Failed to write output file '$OUTPUT_FILE'." >&2
  exit 1
fi
echo "Combined .gitignore created as $OUTPUT_FILE"
