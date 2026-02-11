REGISTRY="http://127.0.0.1:5000"

for repo in $(curl -s "$REGISTRY/v2/_catalog" | jq -r '.repositories[]'); do
  echo "Repository: $repo"
  tags=$(curl -s "$REGISTRY/v2/$repo/tags/list" | jq -r '.tags[]' | grep -v '^latest$')
  tag_dates=""
  for tag in $tags; do
    manifest=$(curl -s -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "$REGISTRY/v2/$repo/manifests/$tag")
    config_digest=$(echo "$manifest" | jq -r '.config.digest')
    created_raw=$(curl -s "$REGISTRY/v2/$repo/blobs/$config_digest" | jq -r '.created' 2>/dev/null)
    if [ "$created_raw" = "null" ] || [ -z "$created_raw" ]; then
      created="1970-01-01 00:00"
    else
      created=$(date -d "$created_raw" +"%Y-%m-%d %H:%M" 2>/dev/null || echo "$created_raw" | sed -E 's/T([0-9]{2}:[0-9]{2}):[0-9]{2}Z/ \\1/')
    fi
    tag_dates="$tag_dates$created|$tag\n"
  done
  # Sortera och skriv ut: taggnamn (datum tid)
  echo -e "$tag_dates" | sort -r | awk -F'|' '{printf "%s (%s)\n", $2, $1}'
  echo
done