#!/bin/bash
set -euo pipefail

# =======================
# ⚙️ Grundinställningar
# =======================
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

REGISTRY_DATA="/home/registry/registry/data"
REGISTRY_CONFIG="/home/registry/registry/config.yml"
REGISTRY_IMAGE="registry:latest"
COMPOSE_FILE="/home/registry/registry/docker-compose.yaml"
LOCK_FILE="/tmp/registry-cleanup.lock"
LOG_FILE="/var/log/registry_GC.log"

REGISTRY_URL="http://127.0.0.1:5000"

# =======================
# 🧾 Loggning
# =======================
exec > >(tee -a "$LOG_FILE") 2>&1
echo -e "\n==============================="
echo "🕓 $(date '+%Y-%m-%d %H:%M:%S') – startar cleanup"
echo "==============================="

# =======================
# 🧱 Skydd mot dubbelkörning
# =======================
if [ -f "$LOCK_FILE" ]; then
  echo "⚠️  Cleanup redan igång – avbryter."
  exit 0
fi
trap 'rm -f "$LOCK_FILE"' EXIT
touch "$LOCK_FILE"

# =======================
# 💥 Säkerhetsnät vid fel
# =======================
trap 'echo "⚠️  Ett fel uppstod – kontrollera loggen!"' ERR

# =======================
# 📊 Diskstatus före
# =======================
USED_BEFORE_KB=$(du -sk "$REGISTRY_DATA" | awk '{print $1}')
USED_BEFORE_H=$(du -sh "$REGISTRY_DATA" | awk '{print $1}')
echo "📏 Före cleanup: $USED_BEFORE_H används"

# =======================
# 🛑 Stoppa registry
# =======================
echo "🛑 Stoppar Docker Registry..."
/usr/bin/docker compose -f "$COMPOSE_FILE" down || true
sleep 2

# =======================
# 🔧 Registry API helpers
# =======================
get_repos() {
  curl -s "$REGISTRY_URL/v2/_catalog" | jq -r '.repositories[]?'
}

get_tags() {
  local repo="$1"
  curl -s "$REGISTRY_URL/v2/$repo/tags/list" | jq -r '.tags[]?'
}

delete_tag() {
  local repo="$1"
  local tag="$2"

  digest=$(curl -sI \
    -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
    "$REGISTRY_URL/v2/$repo/manifests/$tag" \
    | awk -F': ' '/Docker-Content-Digest/ {print $2}' | tr -d '\r')

  if [ -z "$digest" ]; then
    echo "⚠️  Kunde inte hämta digest för $repo:$tag"
    return
  fi

  echo "🗑️  DELETE $repo:$tag"
  curl -s -X DELETE "$REGISTRY_URL/v2/$repo/manifests/$digest" >/dev/null
}

# =======================
# 🔁 Cleanup-logik (SÄKER)
# =======================
for REPO in $(get_repos); do
  echo "🔍 Bearbetar repo: $REPO"

  SEMVER_TAGS=()
  FALLBACK_TAGS=()

  for TAG in $(get_tags "$REPO"); do
    if [[ "$TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      SEMVER_TAGS+=("$TAG")
    elif [[ "$TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+-.+ ]]; then
      FALLBACK_TAGS+=("$TAG")
    fi
  done

  # senaste fallback
  LATEST_FALLBACK=""
  if [ "${#FALLBACK_TAGS[@]}" -gt 0 ]; then
    LATEST_FALLBACK=$(printf "%s\n" "${FALLBACK_TAGS[@]}" | sort -V | tail -n1)
  fi

  # ta bort gamla fallback + latest
  for TAG in $(get_tags "$REPO"); do
    if [[ "$TAG" == "latest" ]]; then
      delete_tag "$REPO" "$TAG"
    elif [[ "$TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      # Spara ALLA SemVer-taggar
      continue
    elif [[ "$TAG" =~ ^[0-9]+\.[0-9]+\.[0-9]+-.+ ]] && [[ "$TAG" != "$LATEST_FALLBACK" ]]; then
      delete_tag "$REPO" "$TAG"
    fi
  done

  echo "✅ $REPO – sparar:"
  for t in "${SEMVER_TAGS[@]}"; do echo "   • $t"; done
  [ -n "$LATEST_FALLBACK" ] && echo "   • $LATEST_FALLBACK"
done
done

# =======================
# 🧽 Garbage collection
# =======================
echo "🧺 Kör garbage collection..."
/usr/bin/docker run --rm \
  -v "$REGISTRY_DATA:/var/lib/registry" \
  -v "$REGISTRY_CONFIG:/etc/docker/registry/config.yml" \
  "$REGISTRY_IMAGE" garbage-collect /etc/docker/registry/config.yml

# =======================
# 🚀 Starta registry igen
# =======================
echo "🚀 Startar Docker Registry igen..."
/usr/bin/docker compose -f "$COMPOSE_FILE" up -d

# =======================
# 📈 Diskstatus efter
# =======================
USED_AFTER_KB=$(du -sk "$REGISTRY_DATA" | awk '{print $1}')
USED_AFTER_H=$(du -sh "$REGISTRY_DATA" | awk '{print $1}')
FREED_GB=$(echo "scale=2; ($USED_BEFORE_KB - $USED_AFTER_KB)/1024/1024" | bc)

echo "📏 Efter cleanup: $USED_AFTER_H används"
echo "💾 Frigjort utrymme: ${FREED_GB} GB"
