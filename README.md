# Save-TerminalHere

Bookmark the current PowerShell directory as a new **Windows Terminal** profile. Next time you open the WT dropdown, the location is one click away — already in the right CWD, with a coloured tab so you can tell sessions apart.

## Why

Windows Terminal's dropdown is great for *static* profiles you set up once, but it has no way to bookmark a running shell — you can't say "remember this terminal, I'll come back to it later in the same folder." This module does exactly that: one command from inside the shell you want to keep, and it appears in the dropdown forever.

## Install (one line)

Copy-paste this into any PowerShell 7 tab:

```powershell
irm https://raw.githubusercontent.com/snowdej/Save-TerminalHere/main/install.ps1 | iex
```

That clones the repo into your user-scope PowerShell modules path, imports
the module, and wires `$PROFILE` so every new shell autoloads it. Re-running
the same line later pulls the latest — safe and idempotent.

### Manual install (no one-liner)

```powershell
git clone https://github.com/snowdej/Save-TerminalHere "$HOME\Documents\PowerShell\Modules\Save-TerminalHere"
Import-Module Save-TerminalHere
Install-SaveTerminalHere
```

If `$HOME\Documents\PowerShell\Modules` isn't on your `$env:PSModulePath`
(OneDrive can redirect Documents), use the path that **is** — the one-liner
installer detects this automatically.

## PowerShell Gallery

Not published yet. Once it is, install becomes:

```powershell
Install-Module Save-TerminalHere -Scope CurrentUser
Install-SaveTerminalHere
```

## Usage

```powershell
# In the directory you want to bookmark:
Save-TerminalHere work

# With explicit tab colour:
Save-TerminalHere -Name "notes" -TabColor "#2EA043"

# Different starting path:
Save-TerminalHere -Name "downloads" -Path "C:\Users\me\Downloads"

# List bookmarks:
Get-TerminalHere

# Remove one:
Remove-TerminalHere work

# Rename (preserves GUID, colour, starting directory):
Rename-TerminalHere work work-archive

# After right-clicking a tab → Color (which is ephemeral),
# commit the colour you liked back to the saved bookmark:
Set-TerminalHereColor work "#1F6FEB"

# Auto-run an arbitrary command when the bookmark opens:
Save-TerminalHere -Name "venv-work" -StartupCommand ". .\venv\Scripts\Activate"

# Open Claude when the bookmark opens (fresh session):
Save-TerminalHere -Name "claude-work" -Claude ""

# Resume a specific Claude session (produces: claude --resume "xyz-123"):
Save-TerminalHere -Name "story-jan-2026" -Claude "xyz-123"

# Shorthand: when -Claude has a value and -Name isn't given,
# the bookmark name defaults to the session ID:
Save-TerminalHere -Claude "note-2026"
# → bookmark "note-2026" runs:  claude --resume "note-2026"
```

### Move your bookmarks to another machine

Export your bookmarks as a portable Windows Terminal **Fragment**. Paths are
normalised to `%USERPROFILE%` / `%OneDrive%` etc. so they're meaningful on
the receiving machine. GUIDs are preserved in the export, and the importer
retags them to the local machine's prefix automatically.

```powershell
# Writes to ~\Desktop\save-terminal-here-<timestamp>.json by default:
Export-TerminalHere -IncludeSchemes

# Or pick a path explicitly:
Export-TerminalHere -Path .\my-terminals.json -IncludeSchemes

# Copy the file to the other PC, then on that PC:
Import-TerminalHere .\my-terminals.json
# Close and reopen Windows Terminal — the bookmarks appear in the dropdown.
```

`Import-TerminalHere` defaults to **Fragment mode**: drops the JSON into
`%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\Save-TerminalHere\`
where WT auto-merges it without touching the target's `settings.json`.
Use `-Mode Merge` if you'd rather inline the profiles into settings.json
directly.

### The right-click colour caveat

Right-clicking a live tab → *Color...* in Windows Terminal only colours the
running tab — it does **not** write back to settings.json. Next time you open
the bookmark, you'll get whatever was saved. Use `Set-TerminalHereColor`
(or `Save-TerminalHere -TabColor … -Force`) to make a chosen colour stick.

## What it writes

A new entry in `settings.json` → `profiles.list` looking like:

```json
{
  "guid": "{5a7e7e7e-1234-5678-9abc-def012345678}",
  "name": "work",
  "commandline": "pwsh.exe -NoLogo",
  "startingDirectory": "C:\\Users\\me\\projects\\work",
  "colorScheme": "Black",
  "tabColor": "#1F6FEB",
  "icon": "ms-appx:///ProfileIcons/{574e775e-4f2a-5b96-ac1e-a2962a402336}.png",
  "suppressApplicationTitle": true,
  "tabTitle": "work",
  "hidden": false
}
```

The new profile is prepended so it shows at the top of the dropdown. The
GUID begins with `5a7e7e7e-` — the module's marker for "I created this"
(see [How bookmarks are identified](#how-bookmarks-are-identified)).

## How bookmarks are identified

Every GUID this module creates starts with **`5a7e7e7e-`** as its first 8-char block. That marker lets `Get-/Rename-/Remove-/Set-TerminalHereColor` reliably identify *our* profiles in `settings.json` without touching any manually-curated profile that happens to also be a pwsh shell.

```
{5a7e7e7e-1234-5678-9abc-def012345678}
   ^^^^^^^^
   the marker — scan settings.json by eye for this
```

### Customising your prefix

Set `$env:STH_GUID_PREFIX` (exactly 8 lowercase hex chars) **before** `Import-Module` to use your own marker:

```powershell
# In $PROFILE, before the Import-Module line:
$env:STH_GUID_PREFIX = 'cafef00d'
Import-Module Save-TerminalHere
```

### Importing bookmarks made on another machine

`Import-TerminalHere` (both `Fragment` and `Merge` modes) **retags incoming GUIDs to match your local prefix**. So if you exported on a machine using the default `5a7e7e7e` and import on a machine using `cafef00d`, the imported bookmarks get fresh `cafef00d-…` GUIDs and are immediately manageable locally.

## Safety

Every write makes a timestamped backup at `settings.json.<yyyyMMdd-HHmmss>.bak` next to the original. If something goes wrong, restore the most recent `.bak`.

## Requirements

- **PowerShell 7+** (`pwsh`). Not installed? `winget install --id Microsoft.PowerShell`. The module uses pwsh-only syntax — Windows PowerShell 5.1 is not supported.
- **git** on PATH. The one-line installer uses `git clone`; the manual install uses `git` directly. `winget install Git.Git` if you don't have it.
- **Windows Terminal** (Store version — settings live under `Microsoft.WindowsTerminal_8wekyb3d8bbwe`).

## License

MIT — see [LICENSE](LICENSE).
