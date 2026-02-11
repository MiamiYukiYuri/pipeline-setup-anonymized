#!/bin/bash

# Användning: ./update-version.sh <yaml-fil> <tjänst-namn> <ny-version>
# Exempel:    ./update-version.sh pipeline.yml service-a 1.2.3

file="$1"
service="$2"
new_version="$3"

awk -v service="$service" -v version="$new_version" '
  $0 ~ "name: "service {
    flag = 1
    print
    next
  }
  flag && $0 ~ /version:/ {
    sub(/version: .*/, "version: " version)
    flag = 0
    print
    next
  }
  { print }
' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"