#!/bin/bash
# OBS! Den här filen är anonymiserad för publicering. Alla företags- och kundspecifika namn är utbytta mot generiska namn.

SCRIPT_DIR="$(dirname "$0")"
CREATE_VAR_GROUP="$SCRIPT_DIR/create-variable-group.sh"
EDIT_ENV="$SCRIPT_DIR/edit-env.sh"

# Read client name and IP
read -p "Client name: " CLIENT
read -p "Client IP: " CLIENT_IP

echo "Adding SSH-key for $CLIENT_IP..."
ssh user@"$CLIENT_IP" "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys" < "$SCRIPT_DIR/keys/deploy_key.pub" || {
  echo "Failed to add SSH key to $CLIENT_IP"
  exit 1
}
echo "SSH-key added for $CLIENT_IP"

echo "Ensuring /home/user/applications exists on $CLIENT_IP..."
ssh user@"$CLIENT_IP" "mkdir -p /home/user/applications" || {
  echo "Failed to create applications folder on $CLIENT_IP"
  exit 1
}
echo "Applications folder ensured on $CLIENT_IP"

# Create secure file
CLIENT=$CLIENT CLIENT_IP=$CLIENT_IP "$EDIT_ENV" --interactive || exit 1

# Create variable group
"$CREATE_VAR_GROUP" --name "$CLIENT" \
                    --client-ip "$CLIENT_IP" \
                    --variable "HOST_NAME=$CLIENT" \
                    --variable "IP=$CLIENT_IP" \
                    --variable "SSH_USER=user" \
                    || exit 1

echo "Client $CLIENT created and configured"
