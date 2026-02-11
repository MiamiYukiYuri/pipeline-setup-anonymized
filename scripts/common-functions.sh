#!/bin/bash


print_fixed_width_header() {
  local text="$1"
  local total_width=35
  local content=" $text "
  local content_length=${#content}
  local inner_width=$((total_width - 6))  # 6 för ### och ###
  local padding_left=$(( (inner_width - content_length) / 2 ))
  local padding_right=$(( inner_width - content_length - padding_left ))

  local left=$(printf "%*s" "$padding_left" "")
  local right=$(printf "%*s" "$padding_right" "")

  echo "###${left}${content}${right}###"
}