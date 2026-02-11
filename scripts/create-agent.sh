# OBS! Den här filen är anonymiserad för publicering. Alla företags- och kundspecifika namn är utbytta mot generiska namn.


# This script is using a PAT to access Azure DevOps, you will need to make your own before running the script.
# You can find the pool name in Azure under Organization settings --> Pipelines --> Agent pools.
# The agent name can be anything, but if you run multiple agents on the same VM they need to be unique.

# Use SSH to access the VM and cd into /agent where you will find the script.
# Run the script in its target folder: ./agent.sh <PAT> <Pool name> <Agent name>

# 1=PAT
# 2=Pool name
# 3=Agent name

AZDO_URL="https://dev.azure.com/company"
AZDO_POOL="$2"
AZDO_TOKEN="$1"
AZDO_AGENT_NAME="$(hostname)-agent-$3"
AGENT_VERSION="4.257.0"
AGENT_DIR="/opt/azdo-agent-$3"
set -e
sudo mkdir -p "$AGENT_DIR"
sudo chown "$(whoami)":"$(whoami)" "$AGENT_DIR"
cd "$AGENT_DIR"
curl -L -O "https://download.agent.dev.azure.com/agent/4.257.0/vsts-agent-linux-x64-4.257.0.tar.gz"
tar zxvf "vsts-agent-linux-x64-$AGENT_VERSION.tar.gz"
sudo ./bin/installdependencies.sh
./config.sh --unattended --url "$AZDO_URL" --auth pat --token "$AZDO_TOKEN" \
  --pool "$AZDO_POOL" --agent "$AZDO_AGENT_NAME" --acceptTeeEula --replace
sudo ./svc.sh install
sudo ./svc.sh start