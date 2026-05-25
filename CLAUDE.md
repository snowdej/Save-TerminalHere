# Save-TerminalHere — project context

PowerShell 7 module that bookmarks the current `$PWD` as a Windows Terminal profile.
Re-opening the bookmark from the WT dropdown lands you back in the same directory,
optionally with a startup command (commonly Claude — fresh or resume-by-id).

## File layout

- `Save-TerminalHere.psm1` — the module (functions, helpers, no top-level code)
- `Save-TerminalHere.psd1` — manifest (version, exports, gallery metadata)
- `install.ps1` — `irm | iex` installer; clones to PSModulePath and wires `$PROFILE`
- `README.md` — user-facing docs (public; keep project-neutral)
- `LICENSE` — MIT
- `.gitignore` — excludes `*.bak`, editor metadata

## Public API surface (8 cmdlets)

| Cmdlet | Purpose |
|---|---|
| `Save-TerminalHere <name>` | Bookmark `$PWD` as a new WT profile |
| `Get-TerminalHere [name-wildcard]` | List bookmarks (filtered by GUID prefix) |
| `Remove-TerminalHere <name>` | Delete a bookmark |
| `Rename-TerminalHere <old> <new>` | Rename in place (preserves GUID, colour, etc.) |
| `Set-TerminalHereColor <name> <#hex>` | Change tab colour only |
| `Export-TerminalHere [-Path] [-IncludeSchemes]` | Emit a portable WT Fragment JSON |
| `Import-TerminalHere <path> [-Mode Fragment\|Merge]` | Install a fragment on this machine |
| `Install-SaveTerminalHere` | Wire `$PROFILE` to autoload the module |

`Save-TerminalHere -Claude` notes:
- `-Claude ""` → emits `claude` (fresh session)
- `-Claude <id>` → emits `claude --continue --resume <id>` (latest matching session, no picker)
- When `-Claude <id>` is given without `-Name`, the bookmark name defaults to `<id>`

## Identification: GUID prefix marker

Every bookmark this module creates has a GUID whose first 8-char group is the prefix:
- Default: `5a7e7e7e`
- Overridable via `$env:STH_GUID_PREFIX` (set before `Import-Module`)

All read/mutate cmdlets filter by this prefix so the module never touches profiles
it didn't create. Manual / hand-curated pwsh profiles in `settings.json` are invisible
to `Get-TerminalHere` and immune to `Remove-TerminalHere`, etc.

## Dev/install topology

Maintainers typically keep two clones:

- A **dev clone** anywhere convenient (e.g. `~/src/Save-TerminalHere`). Edit here.
- An **install copy** under PSModulePath (find with
  `$env:PSModulePath -split [IO.Path]::PathSeparator | Where-Object { $_ -match 'Documents.PowerShell.Modules$' }`).
  Autoloaded by `$PROFILE`; treat as read-only.

Standard change flow:
1. Edit in dev clone
2. `git add … && git commit && git push origin main`
3. `cd <install-copy> && git pull --ff-only` (so the live module sees the change)

## Settings.json

The module reads/writes Windows Terminal's settings.json at:
```
$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json
```

Every write makes a timestamped backup (`settings.json.<yyyyMMdd-HHmmss>.bak`) next
to the original. Restore the most recent `.bak` if anything looks wrong.

## Known gotchas

- **Windows command-line tokenization** mangles inner double quotes in the
  `commandline` field. We avoid this by emitting bare slug values (Claude session
  IDs are alphanumeric+dash). PowerShell backtick-escape (`` `" ``) does NOT survive
  the journey from JSON → WT → CreateProcessW → pwsh.
- **`raw.githubusercontent.com` CDN** caches `install.ps1` for ~5 min. To verify a
  fresh installer immediately after pushing, use the commit-pinned URL
  `…/raw/<sha>/install.ps1` instead of `…/raw/main/install.ps1`.
- **Strict mode + JSON-parsed objects**: accessing a non-existent property throws
  under `Set-StrictMode -Version Latest`. Use `$obj.PSObject.Properties.Name -contains 'foo'`
  before reading optional fields.

## Release process

1. Edit module (`.psm1`) and/or installer (`install.ps1`)
2. Bump `ModuleVersion` in `.psd1`; update `ReleaseNotes` field
3. Update `README.md` if user-visible behaviour changes
4. Smoke-test by re-importing the module in a clean shell
5. Commit, push, pull-into-install

## Style conventions

- PowerShell 7 syntax only (`?:` ternary, null-coalescing). Module is not 5.1-compatible.
- `[CmdletBinding(SupportsShouldProcess)]` on every mutating function
- `ShouldProcess` before every settings.json write
- `Backup-TerminalSettings` before every settings.json write
- `Write-Warning` (not throw) for "no match" cases unless we're sure it's an error
- Bare slugs in `commandline`; avoid inner quoting
