#!/bin/bash

REPO_NAME=""
TAG_VERSION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo-name|-rp)
      REPO_NAME="$2"
      shift 2
      ;;
    --tag-version|-t)
      TAG_VERSION="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 --repo-name <repo-name> --tag-version <tag-version>"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

echo "You chose repo $REPO_NAME and tag $TAG_VERSION"

DIGEST=$(curl -sI -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \http://127.0.0.1:5000/v2/$REPO_NAME/manifests/$REPO_NAME-$TAG_VERSION | \
 grep Docker-Content-Digest | awk '{print $2}' | tr -d $'\r')
echo "Digest for $REPO_NAME and $TAG_VERSION: $DIGEST"