Pipeline Setup (Anonymized)
===========================

This repository is a sanitized, portfolio-style snapshot. It demonstrates how I structure Azure DevOps pipelines, Docker build/deploy flows, and environment management. It is not intended to be used as a ready-to-run project, and it omits or anonymizes production details.

Purpose
-------
- Showcase pipeline design, release automation, and VM deployment flows.
- Illustrate how I organize scripts and templates for maintainability.
- Provide a realistic but anonymized example of infra automation.

What this repo demonstrates
---------------------
- Build and push Docker images to a private registry.
- Manage semantic versioning and release tags.
- Deploy multiple services to multiple customer VMs.
- Manage per-customer env files via Azure DevOps secure files.
- Maintain build agents with safe cleanup routines.

Repository layout
-----------------
- deploy-prod-pipeline.yaml: Deploy pipeline for production targets.
- deploy-test-pipeline.yaml: Deploy pipeline for test targets.
- templates/: Reusable pipeline templates.
  - build-template.yaml: End-to-end build + release + test deploy pipeline.
  - build-and-push.yaml: Docker build/push steps.
  - deploy-template.yaml: VM deployment flow (download envs, copy compose, deploy).
  - download-and-extract-secure-file.yaml: Secure file download and unzip.
  - agent-cleanup-template.yaml: Disk/agent cleanup on build agents.
  - pnpm-semantic-release-template.yaml: semantic-release via pnpm.
  - docker-compose.yml: Example compose file with placeholder registry/service tags.
- scripts/: Helper scripts for Azure DevOps and VM setup.
  - create-agent.sh: Install and register an Azure DevOps agent.
  - create-client.sh: Add SSH key, create folders, create variable group.
  - create-variable-group.sh: Create a variable group with optional secrets.
  - edit-env.sh: Download, edit, and upload env files for a client.
  - replace-secure-file.sh: Upload a secure file (zip of envs) to Azure DevOps.
  - update_version.sh: Update service versions in deploy pipelines.
  - get-images.sh: List registry images with dates.
  - remove-image.sh: Get digest for a tag (for deletion workflows).
  - garbage-collection.sh: Registry cleanup and garbage collection.
- env-keys/: Facit files listing required env keys per service.
- WIP/: Experimental automation for mass env updates.

High-level flow
---------------
1) Build pipeline (templates/build-template.yaml)
  - Runs semantic-release to determine version.
  - Builds and pushes image to the registry.
  - Updates deploy pipelines with new versions.
  - Optionally deploys to test VM on main branch.

2) Deploy pipeline (deploy-prod-pipeline.yaml, deploy-test-pipeline.yaml)
  - Iterates through clients.
  - Downloads secure files and extracts envs.
  - Copies env files and compose file to VM.
  - Runs docker compose and verifies containers.

3) Agent maintenance (templates/agent-cleanup-template.yaml)
  - Cleans Azure DevOps work directories.
  - Prunes Docker images and cache.
  - Optional system log and npm cache cleanup.

Prerequisites (original context)
--------------------------------
These are listed to explain the original environment and assumptions. They are not a promise that the repo will work out of the box.

- Azure DevOps organization, project, and permission to create variable groups.
- A PAT with access to variable groups and secure files.
- Azure CLI with azure-devops extension, plus jq.
- ssh, scp, sshpass, zip, unzip, fzf (for interactive flows).
- Docker and docker compose on target VMs and build agents.
- Node.js and pnpm for semantic-release.

Important environment variables
-------------------------------
- AZURE_DEVOPS_EXT_PAT: PAT used by scripts and Azure CLI.
- GH_TOKEN: Token used by semantic-release in build pipeline.
- SSH_USER, SSH_PASS, AGENT_VM_IP: Used by cleanup and deploy steps.

Secure files and env layout
---------------------------
Secure files are zipped and uploaded to Azure DevOps. The expected layout is:

  ~/.pipelines/secure-files/<CLIENT>/<service>/.env

The deploy pipeline downloads <CLIENT>.zip and extracts to the agent temp directory.

How to read this repo
---------------------
Use this as a guided tour of patterns and choices rather than a how-to for execution.

1) Start with the build flow
  - templates/build-template.yaml ties together versioning, build, push, and deploy.

2) Review the deploy template
  - templates/deploy-template.yaml shows how envs and compose files are moved to VMs.

3) Inspect the helper scripts
  - scripts/edit-env.sh and scripts/replace-secure-file.sh show env file handling.
  - scripts/create-variable-group.sh shows variable group creation patterns.

4) Look at agent maintenance
  - templates/agent-cleanup-template.yaml demonstrates safe cleanup steps.

Script reference
----------------
create-variable-group.sh
  ./scripts/create-variable-group.sh --name <CLIENT> \
	--variable "HOST_NAME=<CLIENT>" --variable "IP=<IP>" --variable "SSH_USER=<USER>" \
	--secret "SSH_PASS=<PASS>"

edit-env.sh
  ./scripts/edit-env.sh --client <CLIENT> --service <SERVICE> --client-ip <IP>
  ./scripts/edit-env.sh --interactive

update_version.sh
  ./scripts/update_version.sh deploy-prod-pipeline.yaml service-a 1.2.3

garbage-collection.sh
  Intended for registry hosts; deletes old tags and runs registry garbage collection.

Notes on anonymization
----------------------
- Hostnames, org names, registry IPs, and credentials are placeholders.
- Replace placeholders such as company, project, REGISTRY_IP:PORT, and pool names.
- Validate permissions before running any script that calls Azure DevOps APIs.

WIP folder
----------
The WIP folder contains experimental scripts to mass-update env files via a YAML plan. These scripts are started but not finished.
