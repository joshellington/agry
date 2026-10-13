# agry

> **Work in progress.** Built for my own setup; expect rough edges and changes.

A tiny macOS menu bar app that keeps your Mac awake while coding agents are
working, blocked, or recently finished, then lets it sleep.

Signals come from Rex program-status records (OSC 7501) and
Claude Code session files. Lid-closed mode, which is optional, uses
`pmset disablesleep` through a narrow sudoers rule.

## Build

Requires macOS 15+ and Swift 6.

```sh
swift test
scripts/bundle.sh   # builds build/Agry.app
```

Config is at `~/Library/Application Support/agry/config.json` (optional).
