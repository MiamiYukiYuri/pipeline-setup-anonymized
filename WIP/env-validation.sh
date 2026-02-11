#!/bin/bash
# filepath: /Users/mias/Desktop/production-node-release/scripts/env-validation.sh

REQUIRED_FILE_PATH=""
ENV_FILES_BASE_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --required-file-path)
      REQUIRED_FILE_PATH="$2"
      shift 2
      ;;
    --env-files-base-path)
      ENV_FILES_BASE_PATH="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 --required-file-path <facit-file> --env-files-base-path <env-files-root-folder>"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$REQUIRED_FILE_PATH" || -z "$ENV_FILES_BASE_PATH" ]]; then
  echo "You need to set both --required-file-path and --env-files-base-path!"
  exit 1
fi

# Find all sections (services) in facit file
services=$(grep '^##### ' "$REQUIRED_FILE_PATH" | sed 's/^##### //' | sed 's/ #####$//' | tr '[:upper:]' '[:lower:]' | tr '_' '-' )

for service in $services; do
  header="##### $(echo "$service" | tr '[:lower:]' '[:upper:]' | tr '-' '_' ) #####"
  facit_keys=$(awk -v h="$header" '
    $0==h {flag=1; next}
    flag && /^##### / {exit}
    flag && $0 == "-------------" {exit}
    flag && !/^#/ && !/^\s*$/ {print $0}
  ' "$REQUIRED_FILE_PATH" | sort | uniq)

  env_file="$ENV_FILES_BASE_PATH/$service/.env"
  if [[ ! -f "$env_file" ]]; then
    echo "❌ Env file missing for service: $service ($env_file)"
    echo "⚠️ Aborting deployment due to missing env file."
    continue
    exit 1
  fi

  # Get all env keys from the env file
  # Ignores white space and comments
  env_keys=$(grep -v "^#" "$env_file" | grep -v "^\s*$" | awk -F= '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}' | sort | uniq)

  # Missing keys
  missing=""
  for key in $facit_keys; do
    if ! echo "$env_keys" | grep -qx "$key"; then
      missing="$missing $key"
    fi
  done

  # Forbidden keys
  forbidden=""
  for key in $env_keys; do
    if ! echo "$facit_keys" | grep -qx "$key"; then
      forbidden="$forbidden $key"
    fi
  done

  if [ -n "$missing" ]; then
    echo "❌ $service is missing required env keys from facit:"
    for k in $missing; do echo "$k"; done
    echo "⚠️ Aborting deployment due to missing env keys."
    exit 1
  fi

  if [ -n "$forbidden" ]; then
    echo "❌ $service contains forbidden env keys (not in facit):"
    for k in $forbidden; do echo "$k"; done
    echo "⚠️ Aborting deployment due to forbidden env keys."
    exit 1
  fi

  if [ -z "$missing" ] && [ -z "$forbidden" ]; then
    echo "✅ Env keys in $service match facit!"
  fi
done