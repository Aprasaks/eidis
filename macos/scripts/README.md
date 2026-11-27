# JARVIS macOS updates and backup retention

Keep the current app at `~/Applications/JARVIS.app`. Previous copies are
stored under `~/.jarvis-lab/app-backups/ (hidden, newest 1 kept)`.

## Installing the next signed release

From the JARVIS repository root:

```bash
bash macos/scripts/package-app.sh
bash macos/scripts/install-app.sh --check
bash macos/scripts/install-app.sh
```

The installer checks both Apple Development signatures, requires a higher
numeric build, stages a new app before replacing the installed one, preserves
the old app for rollback, and opens the new app. **Only after that** does it
delete superseded previous releases, keeping the latest three distinct signed
JARVIS builds. An independent legacy app with a different bundle identifier
is always protected.

To inspect backup cleanup without making any change:

```bash
python3 macos/scripts/prune-app-backups.py --keep 1
```

To do a verified cleanup explicitly:

```bash
python3 macos/scripts/prune-app-backups.py --keep 1 --apply
```

Each actual cleanup writes a list of removed paths in
`~/Library/Logs/JARVIS/maintenance/backup-prune-*.json`.

**Important:** Manual installation that bypasses `install-app.sh` also
bypasses automatic retention. Do not remove the working application,
repository, Keychain entries, AI models, or personal knowledge/data folders
during backup cleanup.
