#!/bin/bash

if ! command -v brew &> /dev/null; then
  echo "Homebrew not found. Please install Homebrew first: https://brew.sh/"
  return 1
fi

required_clis=("sshpass:sshpass" "jq:jq" "az:azure-cli" "fzf:fzf")
for cli in "${required_clis[@]}"; do
  IFS=":" read -r cli_command brew_package <<< "$cli"
  if ! command -v "$cli_command" &> /dev/null; then
    missing_clis+=("$brew_package")
  fi
done

# Install missing CLIs with brew if any are missing
if [ ${#missing_clis[@]} -ne 0 ]; then
  brew install "${missing_clis[@]}"
fi

# Variable to temporarily store SSH password
SERVER_PASSWORD=""

# --- Function to sync facit file with env file ---
sync_facit_file() {
  FACIT_FILE=$(find "$SCRIPT_DIR/../env-keys" -iname "${CLIENT}-env-keys.txt" | head -n1)
  header="##### $(echo "$SERVICE" | tr '[:lower:]' '[:upper:]' | tr '-' '_' ) #####"
  env_keys=$(grep -v "^#" "$ENV_FILE" | grep -v "^\s*$" | awk -F= '{gsub(/^[ \t]+|[ \t]+$/, "", $1); print $1}' | sort | uniq)
  new_section="$header"$'\n'
  for key in $env_keys; do
    echo "DEBUG: Adding key '$key' to facit"
    new_section+="$key"$'\n'
  done
  new_section+="-------------"$'\n'
  tmp_section="$SCRIPT_DIR/new_section.txt"
  echo "$new_section" > "$tmp_section"
  awk -v h="$header" -v f="$tmp_section" '
    BEGIN {
      new_sec = ""
      while ((getline line < f) > 0) {
        new_sec = new_sec line "\n"
      }
      close(f)
      printed = 0
    }
    $0==h {
      printf "%s", new_sec
      skip=1
      next
    }
    skip && (/^##### / || $0=="-------------") {skip=0; next}
    !skip {print}
  ' "$FACIT_FILE" > "$FACIT_FILE.tmp" && mv "$FACIT_FILE.tmp" "$FACIT_FILE"
  rm "$tmp_section"
  echo "✅ Facit file successfully synced with secure file for $SERVICE!"
}

function export-azure-devops-pat(){

  ### --- Azure login and Key Vault retrieval of PAT ---
  APP_ID="GENERIC_APP_ID"
  CLIENT_SECRET="GENERIC_CLIENT_SECRET"
  TENANT_ID="GENERIC_TENANT_ID"
  KEYVAULT_NAME="GENERIC_KEYVAULT"
  SECRET_NAME="GENERIC_SECRET_NAME"

  # Login with Service Principal
  az login --service-principal -u "$APP_ID" -p "$CLIENT_SECRET" --tenant "$TENANT_ID" > /dev/null

  # Fetch PAT from Key Vault (always automatic, no manual handling)
  AZURE_DEVOPS_EXT_PAT=$(az keyvault secret show --vault-name "$KEYVAULT_NAME" --name "$SECRET_NAME" --query value -o tsv 2>/dev/null)
  if [[ $? -ne 0 || -z "$AZURE_DEVOPS_EXT_PAT" ]]; then
    echo "Failed to retrieve PAT from Key Vault. Please check permissions and Key Vault name."
    return 1
  fi
  export AZURE_DEVOPS_EXT_PAT
}

# Find script directory (absolute path)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common-functions.sh"

# Find the directory where this script is located (handles symlinks)
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done

# Initiate variables (must always be here!)
SKIP_REPLACE_SECURED_FILE="false"
FIRST_DOWNLOAD=0
ENV_FILE=""
SERVICE=""
INTERACTIVE_MODE=0
ENVS=()
REMOVALS=()
SECURE_FILES_PATH="$HOME/.pipelines/secure-files"
mkdir -p "$SECURE_FILES_PATH"
SSH_KEY="$SCRIPT_DIR/keys/deploy_key.pub"
GENERIC_URL="https://dev.azure.com/company/project/_apis/distributedtask/securefiles?api-version=7.1-preview.1"

# Check that SECURE_FILES_PATH is set
if [[ -z "$SECURE_FILES_PATH" ]]; then
  echo "Error: SECURE_FILES_PATH is not set. Please export SECURE_FILES_PATH or set it in your environment before running this script."
  exit 1
fi

# --- Function to fetch variable group ID by name ---
ORG="company"
PROJECT="project"
get_variable_group_id_by_name() {
  local org="$1"
  local project="$2"
  local group_name="$3"
  local pat="$4"

  local response
  response=$(curl -s -u ":$pat" \
    "https://dev.azure.com/$org/$project/_apis/distributedtask/variablegroups?api-version=7.0-preview.2")

  local id
  id=$(echo "$response" | jq -r --arg NAME "$group_name" '.value[] | select((.name|ascii_downcase)==($NAME|ascii_downcase)) | .id')

  if [[ -z "$id" ]]; then
    echo "Could not find variable group '$group_name'."
    return 1
  fi
  echo "$id"
}

function get_variable_groups() {
  local org="$1"
  local project="$2"
  local pat="$3"

  local response
  response=$(curl -s -u ":$pat" \
    "https://dev.azure.com/$org/$project/_apis/distributedtask/variablegroups?api-version=7.0-preview.2")

  if [[ -z "$response" || "$response" == "null" ]]; then
    echo "DEBUG: API response is empty or null. Check PAT, network, and Azure permissions."
    return 1
  fi

  local groups
  groups=$(echo "$response" | jq -r '.value[] | select(.name != "Build-variables") | "\(.id): \(.name)"')
  if [[ -z "$groups" ]]; then
    echo "DEBUG: No variable groups found in API response. Raw response: $response"
    return 1
  fi
  echo "$groups"
}

# Prepare arguments
if [[ $# -eq 0 ]]; then
  INTERACTIVE_MODE=1
fi
while [[ $# -gt 0 ]]; do
  case "$1" in
    --client)
      CLIENT="$2"
      shift 2
      ;;
    --service)
      SERVICE="$2"
      shift 2
      ;;
    --env)
      ENVS+=("$2")
      shift 2
      ;;
    --remove)
      REMOVALS+=("$2")
      shift 2
      ;;
    --client-ip)
      CLIENT_IP="$2"
      shift 2
      ;;
    --skip-replace-secure-file)
      SKIP_REPLACE_SECURED_FILE="true"
      shift 1
      ;;
    --interactive)
      INTERACTIVE_MODE=1
      shift 1
      ;;
    --help|-h)
      echo "Usage: $0 --client <client> --service <service> --client-ip <ip-to-vm> --interactive [--env key=val ...] [--remove key ...]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done


check_ssh_key() {
  if [[ ! -f "$SSH_KEY" ]]; then
    echo "SSH-key not found at $SSH_KEY"
    exit 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  check_ssh_key
fi

function create_secure_files_dir() {
  dir=$(find "$SECURE_FILES_PATH" -maxdepth 1 -type d -iname "$CLIENT" | head -n1)
  if [[ -z "$dir" ]]; then
    echo "File path $SECURE_FILES_PATH/$CLIENT does not exist, creating it now..."
    echo "Creating file path for storing env files at: $SECURE_FILES_PATH/$CLIENT"
    mkdir -p "$SECURE_FILES_PATH/$CLIENT"
  else
    echo "File path $SECURE_FILES_PATH/$CLIENT already exists, skipping creation"
    echo "___________________________________"
  fi
}

# Hämta env-filer från repos
function download_prod_env_files() {
  if [[ -z "$SERVER_PASSWORD" ]]; then
    read -s -p "Enter password for $CLIENT: " SERVER_PASSWORD
    echo
  fi
  # Försök först hämta env-filer från applications
  sshpass -p "$SERVER_PASSWORD" ssh -o StrictHostKeyChecking=no lagge@$CURR_CLIENT_IP 'ls -d /home/lagge/applications/*/' 2>/dev/null | grep -q .
  APPS_EXIST=$?
    if [[ $APPS_EXIST -eq 0 ]]; then
    echo "Found service directories in applications, fetching env files..."
      services=$(sshpass -p "$SERVER_PASSWORD" ssh -o StrictHostKeyChecking=no lagge@$CURR_CLIENT_IP 'ls -d /home/lagge/applications/*/')
      for service_path in $services; do
        service_name=$(basename "$service_path")
        RSYNC_OUTPUT=$(sshpass -p "$SERVER_PASSWORD" rsync -avz \
          lagge@$CURR_CLIENT_IP:"$service_path/.env" \
          "$SECURE_FILES_PATH/$CLIENT/$service_name/" 2>&1)
        RSYNC_STATUS=$?
        if [[ $RSYNC_STATUS -ne 0 ]]; then
          echo "❌ Error for $service_name: $RSYNC_OUTPUT"
          if echo "$RSYNC_OUTPUT" | grep -q "Permission denied"; then
            echo "Wrong password or insufficient permissions. Would you like to try again?"
            read -p "Try again with new password? (y/n): " retry
            if [[ $retry =~ ^[JjYy]$ ]]; then
              SERVER_PASSWORD=""
              download_prod_env_files
              return
            else
              echo "Aborting."
              exit 1
            fi
          fi
        fi
      done
    else
    echo "No service directories in applications, trying repos..."
      services=$(sshpass -p "$SERVER_PASSWORD" ssh -o StrictHostKeyChecking=no lagge@$CURR_CLIENT_IP 'ls -d /home/lagge/repos/*/')
      for service_path in $services; do
        service_name=$(basename "$service_path")
        RSYNC_OUTPUT=$(sshpass -p "$SERVER_PASSWORD" rsync -avz \
          lagge@$CURR_CLIENT_IP:"$service_path/.env" \
          "$SECURE_FILES_PATH/$CLIENT/$service_name/" 2>&1)
        RSYNC_STATUS=$?
        if [[ $RSYNC_STATUS -ne 0 ]]; then
          echo "❌ Error for $service_name: $RSYNC_OUTPUT"
          if echo "$RSYNC_OUTPUT" | grep -q "Permission denied"; then
            echo "Wrong password or insufficient permissions. Would you like to try again?"
            read -p "Try again with new password? (y/n): " retry
            if [[ $retry =~ ^[JjYy]$ ]]; then
              SERVER_PASSWORD=""
              download_prod_env_files
              return
            else
              echo "Aborting."
              exit 1
            fi
          fi
        fi
      done
    fi
}

function locate_file_to_edit() {
  ENV_FILE="$SECURE_FILES_PATH/${CLIENT}/${SERVICE}/.env"
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "Download file"
    download_prod_env_files
  else
    if [[ "$FIRST_DOWNLOAD" == 0 ]]; then
      while true; do
        echo ""
        echo "The file '$ENV_FILE' already exists. What would you like to do?"
        echo "1) Download a fresh file (overwrite existing, to always get latest)"
        echo "2) Edit the existing file"
        echo "3) Cancel"
        read -p "Choose an option [1-3]: " choice
        echo ""
        echo "___________________________________"

        case "$choice" in
          1)
            echo "Downloading a new file and overwriting '$ENV_FILE'..."
            rm -rf "$SECURE_FILES_PATH/$CLIENT"
            rm -rf "$SECURE_FILES_PATH/$CLIENT"
            download_prod_env_files
            break
            ;;
          2)
            echo "Continuing with editing the existing file..."
            break
            ;;
          3)
            echo "Operation cancelled."
            exit 0
            ;;
          *)
            echo "Invalid choice. Please enter 1, 2 or 3."
            ;;
        esac
      done
    fi
  fi
}

function display_services_interactivly() {
  services_array=()
  if [[ ! -d "$SECURE_FILES_PATH/$CLIENT" ]]; then
    download_prod_env_files
    FIRST_DOWNLOAD=1
  fi
  for dir in "$SECURE_FILES_PATH/$CLIENT"/*/; do
    [[ -d $dir ]] && services_array+=("$(basename "$dir")")
  done
  while true; do
    echo ""
    echo "-----[ SERVICES ]-----"
    echo ""
    for i in "${!services_array[@]}"; do
      printf "%2d) %s\n" "$((i+1))" "${services_array[$i]}"
    done

    echo ""
    read -p "Select a service: (1-${#services_array[@]}): " selection

    # Validate input
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#services_array[@]} )); then
      chosen_service="${services_array[$((selection-1))]}"
      echo "You selected: $chosen_service"
      SERVICE=$chosen_service
      echo ""
      echo "___________________________________"
      echo ""
      break
    else
      echo "Invalid selection. Please try again."
      echo
    fi
  done
}

if [[ "$INTERACTIVE_MODE" == 0 ]]; then
  # Check that mandatory fields exists
  if [[ -z "$CLIENT" || -z "$SERVICE" ]]; then
    echo "Error: --client and --service are required parameters."
    return 1
    return 1
  fi
      if [[ -z "$AZURE_DEVOPS_EXT_PAT" ]]; then
        echo "Azure DevOps PAT is not set. Fetching from Key Vault..."
        export-azure-devops-pat
      fi

    # --- Automatic lookup of variable group and IP if CLIENT is set ---
    if [[ -n "$CLIENT" ]]; then
      GROUP_NAME="$CLIENT"
      VARIABLE_GROUP_ID=$(get_variable_group_id_by_name "$ORG" "$PROJECT" "$GROUP_NAME" "$AZURE_DEVOPS_EXT_PAT")
      if [[ -z "$VARIABLE_GROUP_ID" ]]; then
        echo "Kunde inte hitta variable group ID för '$GROUP_NAME'!"
        return 1
      fi
      response=$(curl -s -u ":$AZURE_DEVOPS_EXT_PAT" \
        "https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups/$VARIABLE_GROUP_ID?api-version=7.0-preview.2")
      CLIENT=$(echo "$response" | jq -r '.name')
      CLIENT_IP=$(echo "$response" | jq -r '.variables.IP.value')
    fi

    if [[ -z "$CLIENT_IP" ]]; then
      read -p "Provide Client IP: " CLIENT_IP
    fi
    CURR_CLIENT_IP="${CURR_CLIENT_IP:-$CLIENT_IP}"
    create_secure_files_dir
    locate_file_to_edit
    if [[ "$SKIP_REPLACE_SECURED_FILE" == "false" ]]; then
      $SCRIPT_DIR/replace-secure-file.sh
    fi
else
  if [[ -z "$AZURE_DEVOPS_EXT_PAT" ]]; then
    echo "Azure DevOps PAT is not set. Fetching from Key Vault..."
    export-azure-devops-pat
  fi

  # Read variable groups into array (compatible with bash and zsh)
  variable_groups=()
  while IFS= read -r line; do
    variable_groups+=("$line")
  done < <(get_variable_groups "$ORG" "$PROJECT" "$AZURE_DEVOPS_EXT_PAT")


  # Use fzf to select a variable group interactively
  CLIENT=$(printf "%s\n" "${variable_groups[@]}" | fzf --prompt="Select the customer: ")
  VARIABLE_GROUP_ID=$(echo "$CLIENT" | cut -d: -f1 | xargs)
  GROUP_NAME=$(echo "$CLIENT" | cut -d: -f2- | xargs)

  # --- Automatic lookup of variable group and IP if CLIENT is set ---
  if [[ -n "$CLIENT" ]]; then
      response=$(curl -s -u ":$AZURE_DEVOPS_EXT_PAT" \
        "https://dev.azure.com/$ORG/$PROJECT/_apis/distributedtask/variablegroups/$VARIABLE_GROUP_ID?api-version=7.0-preview.2")
      CLIENT=$(echo "$response" | jq -r '.name')
      CLIENT_IP=$(echo "$response" | jq -r '.variables.IP.value')
    else
      echo "No client selected, exiting."
      return 1
    fi

  if [[ -z "$CLIENT_IP" ]]; then
    read -p "Provide Client IP: " CLIENT_IP
  fi
  CURR_CLIENT_IP="${CURR_CLIENT_IP:-$CLIENT_IP}"

  display_services_interactivly
  locate_file_to_edit
  create_secure_files_dir

  echo ""
  while true; do
    print_fixed_width_header "Execution menu"
    print_fixed_width_header "$CLIENT" 
    print_fixed_width_header "$SERVICE"
    echo "___________________________________"
    echo ""
    echo "--[ What would you like to do? ]--"
    echo ""
    echo "1) Show content of env file"
    echo "2) Edit env file with VIM"
    echo "3) Update secure file in Azure"
    echo "4) Switch service"
    echo "5) Cancel"
    echo ""
    read -p "Choose an option [1-5]: " edit_choice

    case "$edit_choice" in
      1)
        clear
        print_fixed_width_header $SERVICE
        cat $ENV_FILE
        read -n 1 -s -r -p "Press any key to exit view mode..."
        clear
        ;;
      2)
        clear
        print_fixed_width_header "$SERVICE"
        echo "Opening $ENV_FILE in editor..."
        sleep 1
        ${EDITOR:-vim} "$ENV_FILE"
        sync_facit_file
        read -n 1 -s -r -p "Press any key to continue..."
        clear
        ;;
      3)
        AZURE_DEVOPS_EXT_PAT="$AZURE_DEVOPS_EXT_PAT" "$SCRIPT_DIR/replace-secure-file.sh" --client $CLIENT
        UPLOAD_STATUS=$?
        if [[ $UPLOAD_STATUS -ne 0 ]]; then
          echo "❌ Failed to upload secure file. Check Azure access and network, then retry."
          read -p "Do you want to try again? (y/n): " retry
          if [[ $retry =~ ^[JjYy]$ ]]; then
            AZURE_DEVOPS_EXT_PAT="$AZURE_DEVOPS_EXT_PAT" "$SCRIPT_DIR/replace-secure-file.sh" --client $CLIENT
          else
            echo "Cancelling upload."
            echo "Cancelling upload."
          fi
        else
          echo "✅ Secure file uploaded to Azure.."
          echo "___________________________________"
          echo ""
        fi
        ;;
      4)
        display_services_interactivly
        locate_file_to_edit
        ;;
      5)
        echo "Operation cancelled."
        SERVER_PASSWORD=""
        exit 0
        ;;
      *)
        echo "Invalid selection, please try again."
        echo ""
        ;;
    esac
  done
fi