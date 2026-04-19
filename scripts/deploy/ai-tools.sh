#!/bin/bash
# AI tools module: OpenCLAW, OpenRouter
# Source this from the main deploy script

set -euo pipefail

if [[ -z "${SCRIPT_DIR:-}" ]]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

_ai_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# shellcheck source=openclaw/install.sh
source "$_ai_dir/openclaw/install.sh"
# shellcheck source=openclaw/config.sh
source "$_ai_dir/openclaw/config.sh"
# shellcheck source=openclaw/governance.sh
source "$_ai_dir/openclaw/governance.sh"

unset _ai_dir
