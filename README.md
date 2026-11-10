# Spark Code Harness

General-purpose software development with OpenCode on your Mac and inference on
your own private, OpenAI-compatible model gateway. Use it for websites, APIs, automation, command-line
tools, desktop applications, data processing, or games. Each project can supply
its own `AGENTS.md` with build, test, and toolchain instructions.

This repository contains configuration and setup tools, **not credentials, model
weights, or details of any particular network**. The new Mac needs the address of
your gateway, its own inference token, and (if your gateway is private) access to
your private network. macOS is the supported platform for this release.

## Set up a new Mac

You do not need Python, Node, Homebrew, or Git to install from a downloaded ZIP.
Your software projects may need their own development tools later.

### 1. Download this repository

Choose **Code → Download ZIP** on GitHub, then extract it. If Git is already
installed, you can instead clone:

```sh
git clone https://github.com/Run-Stratus/spark-code-harness.git
cd spark-code-harness
```

Open Terminal in the extracted repository folder. First install the launcher
without trying to use the private network yet:

```sh
zsh setup.command --skip-token --skip-doctor
```

This installs OpenCode 1.19.4 if OpenCode is missing, copies the harness into
`~/.config/opencode/spark-harness`, and adds its `bin` folder to your `.zshrc`.
It preserves an existing OpenCode 1 installation; OpenCode 2 is not supported.
No existing global OpenCode config or project files are replaced. Re-running
setup updates the harness-owned files and keeps a single shell profile entry.

**Open a new Terminal window** before the next steps.

### 2. Connect the Mac to your private network

If your gateway is only reachable on a private Headscale/Tailscale network,
install the [Tailscale macOS app](https://tailscale.com/download/mac), open it,
and allow the VPN extension when macOS asks. Set `SPARK_HEADSCALE_URL` to your
control server (or let `setup.command` save it), then run:

```sh
spark-code network
```

This starts interactive enrollment with your Headscale server.
Follow the registration page. Give the page's registration/auth ID to your
Headscale administrator for approval, unless your configured identity-provider
flow handles it. The administrator should follow the instructions shown by
your server; CLI commands differ between Headscale versions.

Headscale supports pending enrollment followed by administrator approval.
An automatic email/chat notification or one-click approval inbox is a separate
administration integration; this client installer does not install or assume
one. No reusable Headscale enrollment key or administrator key is included.

After enrollment, network policy must permit this Mac to reach your gateway.
If the gateway speaks plain HTTP, only use it **inside the private VPN**; do not
expose that endpoint to the public internet.

See [Headscale registration](https://headscale.net/stable/ref/registration/) and
[Tailscale custom control servers](https://tailscale.com/docs/how-to/set-up-custom-control-server?tab=macos).

### 3. Set the gateway address and save the new machine's token

`setup.command` asks for the gateway base URL (including `/v1`) and saves it, with no
credentials, to `~/.config/spark-code/endpoint.env`. You can instead export
`SPARK_BASE_URL` yourself. Obtain the token from your gateway's administrator. It must
permit the three model IDs configured below (see "Models").

```sh
spark-code auth
```

Paste the token at the **hidden terminal prompt**, not into chat, a command-line
argument, or a config file. The command verifies access, then saves it as a
macOS Keychain generic password with service `spark-api` and your current user
as the account. An invalid token does not replace the saved credential.

The launcher retrieves the token when it starts and passes it to OpenCode in
the process environment. There is no `.env` credential file and no token in
the repository, shell profile, or config. `spark-code auth` also rotates the
locally saved token; issuing and revoking tokens happens on your gateway separately.

**Network enrollment and the inference token are separate permissions.** The
inference token cannot enroll a Mac in Headscale, and the Headscale login does not
grant model access. This harness cannot mint tokens.

### 4. Verify the complete connection

```sh
spark-code doctor --full
```

This checks authenticated model discovery, coding chat, streaming with a
16,384-token request ceiling (set `SPARK_EXPECT_REASONING=1` to also require
separate reasoning output), image understanding using a small red/blue fixture,
and `OK` responses through OpenCode for all three models. It exits nonzero on a failed check and never prints the credential.
The diagnostic OpenCode calls deny tools so they do not edit your project.
Without `--full`, doctor runs only the API checks.

If the Mac is already enrolled and the token is in Keychain, a single
`zsh setup.command` installs the harness and runs all checks.

### 5. Start coding

Go to the project you want it to work on:

```sh
cd /path/to/your/project
spark-code
```

Or run one request:

```sh
spark-code run "Inspect this project, explain its architecture, and identify its test commands."
```

For a new project, create an empty folder first, then launch Spark Code there
and describe what you want to build. Start with the intended behavior, target
platform, constraints, and what a successful result should do.

The orchestrator plans and delegates; the coder implements and tests; the
critic reviews code and images. The harness supplies general instructions,
while a project's `AGENTS.md` adds its specific validation commands. It does
not install project toolchains such as Xcode, Python packages, Node, Godot,
Unity, or Blender automatically.

## Models

All providers use the same gateway (`SPARK_BASE_URL`). Three roles are configured, and
you choose which model fills each one. Put **any model your gateway serves** in each
slot with these settings (environment variables or `endpoint.env`):

| Role | Setting | Default model ID | Needs |
| --- | --- | --- | --- |
| Orchestrator | `SPARK_MODEL_ORCHESTRATOR` | `spark-orchestrator` | Strong reasoning and planning |
| Coder | `SPARK_MODEL_CODER` | `spark-coder` | Code generation and tool use |
| Critic | `SPARK_MODEL_CRITIC` | `spark-critic` | Text and image input (review) |

The defaults are generic names. Either create gateway aliases with those names that
point at your models, or set the variables to the real model IDs your gateway
advertises at `/v1/models`. The orchestrator is configured as a reasoning model;
reasoning is optional. The model context setting in `config/opencode.json` is 131,072
and the output ceiling is 16,384; edit them to match your models.

Normal coding retains the original harness's native host access: terminal,
file edits, and web fetch are allowed. **There is no container sandbox.**
The general instructions require explicit authorization for publishing,
deploying, deleting user data, or changing production services. These are
instructions to the model, not an operating-system security boundary.

`spark-code` uses this harness's config via `OPENCODE_CONFIG` and disables
external plugins for the baseline launch. It limits enabled providers to the
three configured providers. OpenCode can still merge project/global settings; inspect
project instructions and config before using an unfamiliar repository.

## Configuration and updates

Non-secret environment overrides are supported:

| Variable | Default | Use |
| --- | --- | --- |
| `SPARK_BASE_URL` | none (required) | Gateway, including `/v1` |
| `SPARK_HEADSCALE_URL` | none | Enrollment server for `spark-code network` |
| `SPARK_MODEL_ORCHESTRATOR`, `SPARK_MODEL_CODER`, `SPARK_MODEL_CRITIC` | `spark-orchestrator`, `spark-coder`, `spark-critic` | Model IDs for each role |
| `SPARK_ENDPOINT_FILE` | `~/.config/spark-code/endpoint.env` | Optional file of `KEY=VALUE` settings (no credentials) |
| `SPARK_EXPECT_REASONING` | unset | Set to 1 to make `doctor` require separate reasoning output |
| `SPARK_KEYCHAIN_SERVICE` | `spark-api` | Separate local credential slot |
| `SPARK_OPENCODE_BIN` | discovered on PATH, then `~/.opencode/bin/opencode` | Specific OpenCode 1 executable |
| `SPARK_INSTALL_DIR` | `~/.config/opencode/spark-harness` | Setup destination |
| `SPARK_SHELL_RC` | `~/.zshrc` | Setup's shell profile target |

Only set a gateway you trust: the launcher sends the saved credential to that
endpoint. Keep these overrides in your own shell profile if needed. Never set
a token in the repository or shell profile.

To update the harness, download the latest ZIP or pull the repository, then
run `zsh setup.command` again. It keeps the Keychain credential. Automatic
OpenCode updates are disabled for the launcher; validate a new OpenCode version
with `doctor --full` before adopting it.

For access failures: enroll with `spark-code network`, check the VPN policy,
then check/rotate the inference credential with `spark-code auth`. A missing
model ID requires a gateway or model configuration update, not a guessed
replacement ID. A busy gateway can add queue time to diagnostics.

## Development checks

Python is needed only to run repository tests, not to install or use the harness:

```sh
python3 -m unittest discover -s tests -v
zsh -n setup.command bin/spark-code scripts/common.zsh
zsh ./bin/spark-code doctor --full
```

The first checks run locally without network credentials. The last is the live
acceptance check and requires network access to your gateway plus a Keychain token. Do not
commit credentials, machine-private keys, or diagnostic logs.

Upstream references: [OpenCode installation](https://opencode.ai/docs/) and
[configuration](https://opencode.ai/docs/config/).
