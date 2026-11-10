#!/bin/zsh
set -euo pipefail
unsetopt xtrace verbose
umask 077
export SPARK_HARNESS_HOME="${0:A:h}"
source "$SPARK_HARNESS_HOME/scripts/common.zsh"
require_mac
require_model_ids

skip_install=0
skip_token=0
skip_doctor=0
for arg in "$@"; do
  case "$arg" in
    --skip-install) skip_install=1 ;;
    --skip-token) skip_token=1 ;;
    --skip-doctor) skip_doctor=1 ;;
    --help|-h)
      print 'Usage: zsh setup.command [--skip-install] [--skip-token] [--skip-doctor]'
      print 'Installs Spark Code, adds its launcher to .zshrc, and checks the connection.'
      print 'Use --skip-token --skip-doctor to install before network enrollment.'
      exit 0 ;;
    *) fail "Unknown option: $arg"; exit 1 ;;
  esac
done

source_dir="$SPARK_HARNESS_HOME"
install_dir="${SPARK_INSTALL_DIR:-$HOME/.config/opencode/spark-harness}"
shell_rc="${SPARK_SHELL_RC:-$HOME/.zshrc}"
install_dir="${install_dir:A}"
shell_rc="${shell_rc:A}"
[[ "$install_dir" != "$source_dir" ]] || { fail 'Run setup from the downloaded repository, not the installed copy.'; exit 1; }
if [[ -e "$install_dir" && ! -f "$install_dir/VERSION" ]]; then
  fail "Refusing to replace an unrelated directory: $install_dir"
  exit 1
fi

if ! find_opencode 2>/dev/null; then
  (( ! skip_install )) || { fail '--skip-install requires an existing OpenCode installation.'; exit 1; }
  print -r -- "Installing OpenCode $SPARK_TESTED_OPENCODE_VERSION using the official installer."
  installer=$(/usr/bin/mktemp -t spark-opencode-install)
  trap '/bin/rm -f -- "$installer"' EXIT
  /usr/bin/curl -fsSL --connect-timeout 15 --max-time 120 https://opencode.ai/install -o "$installer"
  /bin/bash "$installer" --version "$SPARK_TESTED_OPENCODE_VERSION" --no-modify-path
  /bin/rm -f -- "$installer"
  trap - EXIT
  find_opencode
fi
version=$("$OPENCODE_BIN" --version)
[[ "$version" == 1.* ]] || { fail 'OpenCode 2 is installed. This harness currently requires OpenCode 1; no installation was replaced.'; exit 1; }
print -r -- "Using OpenCode $version (tested baseline: $SPARK_TESTED_OPENCODE_VERSION)."

mkdir -p "$install_dir"
for directory in bin config instructions scripts assets; do
  mkdir -p "$install_dir/$directory"
  /bin/cp -R "$source_dir/$directory/." "$install_dir/$directory/"
done
/bin/cp "$source_dir/VERSION" "$source_dir/README.md" "$install_dir/"
/bin/chmod 700 "$install_dir/bin/spark-code"

mkdir -p "${shell_rc:h}"
[[ -e "$shell_rc" ]] || : > "$shell_rc"
start_count=$(/usr/bin/grep -c '^# >>> spark-code >>>$' "$shell_rc" || true)
end_count=$(/usr/bin/grep -c '^# <<< spark-code <<<$' "$shell_rc" || true)
[[ "$start_count" == "$end_count" && "$start_count" -le 1 ]] || {
  fail 'The existing spark-code block in the shell profile is malformed; no profile changes made.'; exit 1;
}
profile_tmp=$(/usr/bin/mktemp "${shell_rc}.spark.XXXXXX")
trap '/bin/rm -f -- "$profile_tmp"' EXIT
/usr/bin/awk '
  /^# >>> spark-code >>>$/ {inside=1; next}
  /^# <<< spark-code <<</ {inside=0; next}
  !inside {print}
' "$shell_rc" > "$profile_tmp"
{
  print '# >>> spark-code >>>'
  printf 'export PATH=%q:"$PATH"\n' "$install_dir/bin"
  print '# <<< spark-code <<<'
} >> "$profile_tmp"
/bin/chmod "$(/usr/bin/stat -f '%Lp' "$shell_rc")" "$profile_tmp"
/bin/mv "$profile_tmp" "$shell_rc"
trap - EXIT
export SPARK_HARNESS_HOME="$install_dir"

print -r -- "Installed Spark Code in $install_dir"

# Save the gateway endpoint (not a credential) so nothing about your network lives in the repository.
if [[ -z "$SPARK_BASE_URL" ]]; then
  if [[ -t 0 ]]; then
    read -r 'SPARK_BASE_URL?Gateway base URL including /v1 (leave blank to set later): '
    read -r 'SPARK_HEADSCALE_URL?Headscale/Tailscale control-server URL for enrollment (optional): '
    if [[ -n "$SPARK_BASE_URL" ]]; then
      mkdir -p "${SPARK_ENDPOINT_FILE:h}"
      {
        print -r -- "SPARK_BASE_URL=$SPARK_BASE_URL"
        [[ -z "$SPARK_HEADSCALE_URL" ]] || print -r -- "SPARK_HEADSCALE_URL=$SPARK_HEADSCALE_URL"
      } > "$SPARK_ENDPOINT_FILE"
      /bin/chmod 600 "$SPARK_ENDPOINT_FILE"
      print -r -- "Saved endpoint settings to $SPARK_ENDPOINT_FILE"
    fi
  else
    print -r -- "SPARK_BASE_URL is not set. Export it, or create $SPARK_ENDPOINT_FILE with a SPARK_BASE_URL=... line."
  fi
fi
if (( ! skip_token )) && [[ -n "$SPARK_BASE_URL" ]]; then
  if /usr/bin/security find-generic-password -a "$USER" -s "$SPARK_KEYCHAIN_SERVICE" -w >/dev/null 2>&1; then
    print 'Using the existing Spark credential in Keychain.'
  else
    print 'This Mac must be enrolled on your private network first. If it is not, press Ctrl-C and follow the README.'
    store_credential
  fi
fi
if (( ! skip_doctor )); then
  if [[ -z "$SPARK_BASE_URL" ]]; then
    print 'Skipping the connection check because no gateway URL is configured yet.'
  else
    "$install_dir/bin/spark-code" doctor --full
  fi
fi
print 'Setup finished. Open a new terminal, go to your project directory, and run spark-code.'
print 'For enrollment: spark-code network. For a new token: spark-code auth.'
