#!/bin/bash
# OBS! Den här filen är anonymiserad för publicering. Alla företags- och kundspecifika namn är utbytta mot generiska namn.

source "$(dirname "$0")/common-functions.sh"

NAME=""
CLIENT_IP=""
VARIABLES=()
SECRETS=()
PROJECT="project"
ORG="https://dev.azure.com/company"
INTERACTIVE_MODE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        NAME="$2"
        shift 2
        ;;
      --variable)
        VARIABLES+=("$2")
        shift 2
        ;;
      --secret)
        SECRETS+=("$2")
        shift 2
        ;;
      --client-ip)
        CLIENT_IP="$2"
        shift 2
        ;;
      --interactive|-i)
        INTERACTIVE_MODE=1
        break
        ;;
      --help|-h)
        echo "Usage: $0 --name <name> --interactive 'flag for interactive mode' [--variable key=val ...]"
        exit 0
        ;;
      *)
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

function add_interactively() {
  clear
  print_fixed_width_header "Add variable menu"
  print_fixed_width_header "Variable Group: $NAME"
  echo ""
  echo "Provide the variables you want to add in key=value format, separated by space."
  echo "Mandatory variables are HOST_NAME, IP and SSH_USER."
  echo "Remember that the variable HOST_NAME needs to be named exactly the same as the client name, ex. TestKund3."
  read envs
  VARIABLES+=($envs)
}


function add_secrets_interactively() {
  clear
  print_fixed_width_header "Add secret menu"
  print_fixed_width_header "Variable Group: $NAME"
  echo ""
  echo "Provide the secrets you want to add in key=value format, separated by space."
  echo "The password variable is mandatory and has to be named SSH_PASS."
  read envs
  SECRETS+=($envs)
}

function create-variable-group() {
  # Create variable group and save it as a variable
  create_result=$(az pipelines variable-group create \
    --name "$NAME" \
    --variables "${VARIABLES[@]}" \
    --organization "$ORG" \
    --project "$PROJECT" \
    --authorize true \
    --output json)

  # Extract id with jq
  GROUP_ID=$(echo "$create_result" | jq -r '.id')

  # Check
  if [[ -n "$GROUP_ID" ]]; then
    echo "Variable group created with ID: $GROUP_ID"
  else
    echo "Failed to extract group ID!" 
    exit 1
  fi

  if [[ -n "$SECRETS" ]]; then
    for secret_entry in "${SECRETS[@]}"; do
      KEY="${secret_entry%%=*}"
      VALUE="${secret_entry#*=}"

      echo "Adding secret variable: $KEY"

      az pipelines variable-group variable create \
        --group-id "$GROUP_ID" \
        --name "$KEY" \
        --secret true \
        --value "$VALUE" \
        --organization "$ORG" \
        --project "$PROJECT" \
        --only-show-errors
    done
  fi
  [[ $INTERACTIVE_MODE == 1 ]] && sleep 3
}
if [[ $INTERACTIVE_MODE == 0 ]]; then
  if [[ -z $NAME || -z $VARIABLES || -z $AZURE_DEVOPS_EXT_PAT ]]; then
    echo "Error: --name and --variable are required! AZURE_DEVOPS_EXT_PAT ENV is also required to be set."
    exit 1
  fi
  create-variable-group
else
  read -p "Provide Variable Group name eg TestKund3: " NAME
  if [[ -z $AZURE_DEVOPS_EXT_PAT ]]; then
    echo "I could not locate a Azure token"
    read -s -p "Please provide your token" AZURE_DEVOPS_EXT_PAT
    echo ""
  fi

   while true; do
      clear
      print_fixed_width_header "Execution menu"
      print_fixed_width_header "Variable Group: $NAME"
      echo ""
      echo "What would you like to do?"
      echo "1) Add variables"
      echo "2) Add secret variable"
      echo "3) Create group"
      echo "4) Cancel"
      read -p "Choose an option [1-4] " edit_choice

      case $edit_choice in
      1)
        add_interactively
        ;;
      2)
        add_secrets_interactively
        ;;
      3)
        create-variable-group
        ;;
      4)
        echo "Operation canceled"
        exit 0
        ;;
      esac
    done

fi