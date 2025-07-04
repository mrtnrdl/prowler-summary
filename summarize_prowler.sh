#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Function definitions
function usage() {
  echo "Usage: $0 [options] [file1.csv file2.csv ...]"
  echo "Options:"
  echo "  -h        Show this help message and exit"
  echo
  echo "Description:"
  echo "  This script summarizes Prowler CSV output by counting unique CHECK_IDs (issues) that are not muted, grouped by AWS account. It outputs a summary CSV file (summary.csv) with columns: Issue, Count, Accounts. You can provide one or more CSV files as arguments, or pipe input via stdin."
  echo
  echo "Examples:"
  echo "  $0 prowler-output.csv"
  echo "  cat prowler-output.csv | $0"
  exit 1
}

# Parse command-line arguments
while getopts ":h" opt; do
  case ${opt} in
  h)
    usage
    ;;
  \?)
    echo "Invalid option: -$OPTARG" >&2
    usage
    ;;
  esac
done

# Main script logic
main() {
  # Accept file arguments or read from stdin
  output_file="summary.csv"
  tmp_input="$(mktemp)"

  if [[ $# -gt 0 ]]; then
    cat "$@" >"$tmp_input"
  else
    cat - >"$tmp_input"
  fi

  # Get header line and find column numbers (semicolon separated)
  header=$(head -n 1 "$tmp_input")
  # Debug: print header and columns
  echo "[DEBUG] Header: $header" >&2
  IFS=';' read -r -a cols <<<"$header"
  for i in "${!cols[@]}"; do
    col="${cols[$i]}"
    col_trimmed="$(echo "$col" | xargs)" # trim whitespace
    echo "[DEBUG] Column $i: '$col_trimmed' (raw: '$col')" >&2
    case "$col_trimmed" in
    CHECK_ID) issue_col=$((i + 1)) ;;
    MUTED) muted_col=$((i + 1)) ;;
    ACCOUNT_UID) account_col=$((i + 1)) ;;
    esac
  done

  if [[ -z "$issue_col" || -z "$muted_col" || -z "$account_col" ]]; then
    echo "Could not find required columns in CSV header." >&2
    rm "$tmp_input"
    exit 1
  fi

  awk -F';' -v issue_col="$issue_col" -v muted_col="$muted_col" -v account_col="$account_col" '
    NR==1 { next } # skip header
    tolower($muted_col) == "true" { next }
    {
        issue = $issue_col
        account = $account_col
        gsub(/^\"|\"$/, "", issue)
        gsub(/^\"|\"$/, "", account)
        key = issue
        count[key]++
        if (accounts[key] == "") {
            accounts[key] = account
        } else if (index(";" accounts[key] ";", ";" account ";") == 0) {
            accounts[key] = accounts[key] ";" account
        }
    }
    END {
        print "Issue,Count,Accounts"
        for (k in count) {
            print k "," count[k] "," accounts[k]
        }
    }' "$tmp_input" >"$output_file"

  echo "Summary written to $output_file"
  rm "$tmp_input"
}

# Call main function
main "$@"

