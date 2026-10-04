#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
WhatsAppBridge/Runtime/node --test Tests/MailReaderChecks.mjs
