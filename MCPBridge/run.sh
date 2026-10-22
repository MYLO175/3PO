#!/bin/zsh
set -euo pipefail
adapter_dir="$(cd "$(dirname "$0")" && pwd -P)"
bundled_node="$adapter_dir/../WhatsAppBridge/Runtime/node"
if [[ -x "$bundled_node" ]]; then
  exec "$bundled_node" "$adapter_dir/server.mjs"
fi
exec node "$adapter_dir/server.mjs"
