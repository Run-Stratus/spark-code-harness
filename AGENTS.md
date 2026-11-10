# Working on this harness

Keep the repository free of credentials and machine-specific private keys.
Only placeholders or environment references may appear in configuration. Do not commit real hostnames, IP addresses, or model names for a specific deployment; those come from `SPARK_*` settings.
Do not copy credentials from a developer's Keychain into fixtures or logs.

This is a macOS-first, zsh-based bootstrap using built-in macOS tools. It must
not require Python, Node, Homebrew, or Git to install from an extracted ZIP.
The installed launcher must preserve the caller's working directory and load
the Spark credential from Keychain at process start.

Run `python3 -m unittest discover -s tests -v` for local contract tests and
`zsh -n setup.command bin/spark-code scripts/common.zsh` for shell syntax.
Live validation is `zsh ./bin/spark-code doctor --full` on an enrolled Mac with a
credential. Never mint tokens, change the private network or gateway, or deploy server changes
as a side effect of a client test.
