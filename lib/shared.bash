#!/usr/bin/env bash

plugin_read_list() {
  local prefix="$1"
  local i=0
  while true; do
    local var="${prefix}_${i}"
    local value="${!var:-}"
    [[ -z "$value" ]] && break
    echo "$value"
    (( i++ ))
  done
}
