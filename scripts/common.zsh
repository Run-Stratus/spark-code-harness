# Shared by setup.command and bin/spark-code. Never enable shell tracing here.
unsetopt xtrace verbose

# Non-secret settings. Environment variables win; otherwise an optional endpoint file is read.
# The file holds KEY=VALUE lines only (no credentials) and is never executed.
SPARK_ENDPOINT_FILE="${SPARK_ENDPOINT_FILE:-$HOME/.config/spark-code/endpoint.env}"
load_endpoint_file() {
  local line key value
  [[ -r "$SPARK_ENDPOINT_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ '^(SPARK_BASE_URL|SPARK_HEADSCALE_URL|SPARK_MODEL_ORCHESTRATOR|SPARK_MODEL_CODER|SPARK_MODEL_CRITIC)=(.*)$' ]] || continue
    key="${match[1]}"; value="${match[2]}"
    [[ -n "${(P)key:-}" ]] || export "$key=$value"
  done < "$SPARK_ENDPOINT_FILE"
}
load_endpoint_file

# Gateway: the OpenAI-compatible base URL of your inference gateway, including /v1 (no default).
export SPARK_BASE_URL="${SPARK_BASE_URL:-}"
# Optional: your Headscale/Tailscale control-server URL, used only by `spark-code network`.
export SPARK_HEADSCALE_URL="${SPARK_HEADSCALE_URL:-}"
# Model IDs for the three roles. Defaults are generic names; point your gateway's aliases at the
# models you want, or set these variables to the real model IDs your gateway advertises.
export SPARK_MODEL_ORCHESTRATOR="${SPARK_MODEL_ORCHESTRATOR:-spark-orchestrator}"
export SPARK_MODEL_CODER="${SPARK_MODEL_CODER:-spark-coder}"
export SPARK_MODEL_CRITIC="${SPARK_MODEL_CRITIC:-spark-critic}"
SPARK_KEYCHAIN_SERVICE="${SPARK_KEYCHAIN_SERVICE:-spark-api}"
SPARK_TESTED_OPENCODE_VERSION=1.19.4

fail() { print -u2 -r -- "Error: $*"; return 1; }
require_mac() { [[ "$(uname -s)" == Darwin ]] || fail 'This release supports macOS.'; }
require_model_ids() {
  local id
  for id in "$SPARK_MODEL_ORCHESTRATOR" "$SPARK_MODEL_CODER" "$SPARK_MODEL_CRITIC"; do
    [[ "$id" =~ '^[A-Za-z0-9._:/-]+$' ]] || { fail 'Model IDs may only contain letters, digits and . _ : / -'; return 1; }
  done
}
require_gateway() {
  [[ -n "$SPARK_BASE_URL" ]] || {
    fail "SPARK_BASE_URL is not set. Export it or run setup.command (it saves it to $SPARK_ENDPOINT_FILE)."; return 1;
  }
}

load_credential() {
  SPARK_API_KEY=$(/usr/bin/security find-generic-password -a "$USER" -s "$SPARK_KEYCHAIN_SERVICE" -w 2>/dev/null) || {
    fail 'No Spark token in Keychain. Run spark-code auth.'; return 1;
  }
  [[ -n "$SPARK_API_KEY" && "$SPARK_API_KEY" != *$'\n'* && "$SPARK_API_KEY" != *$'\r'* ]] || {
    fail 'The Keychain token is empty or malformed.'; return 1;
  }
  export SPARK_API_KEY
}

find_opencode() {
  local candidate
  for candidate in "${SPARK_OPENCODE_BIN:-}" "$(command -v opencode 2>/dev/null || true)" "$HOME/.opencode/bin/opencode"; do
    [[ -n "$candidate" && -x "$candidate" ]] || continue
    OPENCODE_BIN="$candidate"
    return 0
  done
  fail 'OpenCode is missing. Run setup.command.'
}

prepare_opencode() {
  find_opencode || return 1
  local version
  version=$("$OPENCODE_BIN" --version 2>/dev/null) || return 1
  [[ "$version" == 1.* ]] || { fail "OpenCode 1 is required (tested: $SPARK_TESTED_OPENCODE_VERSION); found $version."; return 1; }
  export OPENCODE_CONFIG="$SPARK_HARNESS_HOME/config/opencode.json"
  export OPENCODE_DISABLE_AUTOUPDATE=1
  # Python/subprocess callers sometimes retain a stale PWD. Keep project detection correct.
  export PWD="$(pwd -P)"
}

json_check() {
  /usr/bin/osascript -l JavaScript "$SPARK_HARNESS_HOME/scripts/check-json.js" "$@"
}

# Only curl's config pipe receives the credential, never its command-line arguments.
# Responses stay in memory; error bodies are deliberately not printed.
api_request() {
  local route="$1" payload="${2:-}" escaped result http_status
  require_gateway || return 1
  [[ "$SPARK_BASE_URL" == http://* || "$SPARK_BASE_URL" == https://* ]] || {
    fail 'SPARK_BASE_URL must be an HTTP(S) URL.'; return 1;
  }
  escaped="${SPARK_API_KEY//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  local -a args
  args=(--silent --show-error --connect-timeout 8 --max-time 120 --config - --write-out $'\n%{http_code}' "${SPARK_BASE_URL%/}/$route")
  [[ -z "$payload" ]] || args+=(--header 'Content-Type: application/json' --data-binary "$payload")
  if ! result=$(printf 'header = "Authorization: Bearer %s"\n' "$escaped" | /usr/bin/curl "${args[@]}" 2>/dev/null); then
    fail 'The gateway did not respond. Check your network access (spark-code network) and SPARK_BASE_URL.'; return 1
  fi
  http_status="${result##*$'\n'}"
  API_BODY="${result%$'\n'*}"
  [[ "$http_status" == 200 ]] || {
    case "$http_status" in
      401|403) fail "The gateway rejected access (HTTP $http_status). Check the token and its model permissions." ;;
      *) fail "The gateway returned HTTP $http_status. Response body withheld to keep diagnostics credential-free." ;;
    esac
    return 1
  }
}

verify_models() {
  api_request models || return 1
  print -rn -- "$API_BODY" | json_check models "$SPARK_MODEL_ORCHESTRATOR" "$SPARK_MODEL_CODER" "$SPARK_MODEL_CRITIC"
}

store_credential() {
  local token
  [[ -t 0 ]] || { fail 'Run spark-code auth in a terminal; credentials are entered locally, not as command arguments.'; return 1; }
  read -rs 'token?Spark API token (hidden): '
  print
  [[ -n "$token" && "$token" != *$'\n'* && "$token" != *$'\r'* ]] || { fail 'No valid token entered.'; return 1; }
  SPARK_API_KEY="$token"
  verify_models || { unset token SPARK_API_KEY; return 1; }
  if ! /usr/bin/security add-generic-password -U -a "$USER" -s "$SPARK_KEYCHAIN_SERVICE" -w "$token" >/dev/null 2>&1; then
    unset token SPARK_API_KEY
    fail 'Keychain could not save the token.'; return 1
  fi
  unset token SPARK_API_KEY
  print 'Token verified and saved in macOS Keychain.'
}
