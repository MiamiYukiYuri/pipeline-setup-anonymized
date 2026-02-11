#!/bin/bash
# OBS! Den här filen är anonymiserad för publicering. Alla företags- och kundspecifika namn är utbytta mot generiska namn.

GENERIC_URL="https://dev.azure.com/company/project/_apis/distributedtask/securefiles?api-version=7.1-preview.1"
SECURE_FILES_PATH="$HOME/.pipelines/secure-files"


while [[ $# -gt 0 ]]; do
  case "$1" in
    --client)
      CLIENT="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 --client <client>"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done


function replace_secure_file(){
  ZIP_FILE_PATH="$SECURE_FILES_PATH/${CLIENT}.zip"
  (
    cd "$SECURE_FILES_PATH" && zip -r "$ZIP_FILE_PATH" "$CLIENT"
  )


  FILE_ID=$(curl -s -H "Authorization: Bearer $AZURE_DEVOPS_EXT_PAT" \
    "${GENERIC_URL}" | \
    jq -r --arg name "${CLIENT}.zip" '.value[] | select(.name==$name) | .id')

  if [[ -n "$FILE_ID" && "$FILE_ID" != "null" ]]; then
    DELETE_URL="https://dev.azure.com/company/project/_apis/distributedtask/securefiles/${FILE_ID}?api-version=7.1-preview.1"
    echo "Secure file exists with ID $FILE_ID. Deleting it..."
    curl -s -X DELETE -H "Authorization: Bearer $AZURE_DEVOPS_EXT_PAT" \
      "${DELETE_URL}"
    echo "Deleted old secure file."
  else
    echo "No existing secure file found. Proceeding to upload."
  fi

  # 2. Upload new secure file
  echo $ZIP_FILE_PATH
  echo "Uploading new secure file ${CLIENT}.zip..."
  UPLOAD_RESPONSE=$(curl -s -X POST -H "Authorization: Bearer $AZURE_DEVOPS_EXT_PAT" \
    -H "Content-Type: application/octet-stream" \
    --data-binary @"${ZIP_FILE_PATH}" \
    "${GENERIC_URL}&name=${CLIENT}.zip")
  NEW_FILE_ID=$(echo $UPLOAD_RESPONSE | jq '.id' | tr -d '"')

  echo "Upload complete."

update_secure_file_permissions_endpoint="https://dev.azure.com/company/project/_apis/pipelines/pipelinepermissions/securefile/${NEW_FILE_ID}?api-version=7.0-preview.1"
    curl -X PATCH \
      -H "Authorization: Bearer $AZURE_DEVOPS_EXT_PAT" \
      -H 'Content-Type: application/json' \
      --data-raw '{
          "allPipelines": {
            "authorized": true
          }
        }' \
      "$update_secure_file_permissions_endpoint"

  echo "Granted permissions for all Pipelines to new secure file"
  sleep 10
}

replace_secure_file