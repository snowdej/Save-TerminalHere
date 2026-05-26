#Requires -Version 7.0
Set-StrictMode -Version Latest

$script:SettingsPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'

# Every GUID this module creates starts with this prefix so we can reliably
# identify "our" profiles in settings.json without depending on heuristics
# like commandline shape. WT doesn't validate GUID randomness; this is just
# a string match.
#
# Default is '5a7e7e7e'. Override per-machine by setting $env:STH_GUID_PREFIX
# (8 lowercase hex chars) in $PROFILE *before* Import-Module Save-TerminalHere.
$script:DefaultGuidPrefix = '5a7e7e7e'
$script:GuidPrefix = if ($env:STH_GUID_PREFIX) {
    if ($env:STH_GUID_PREFIX -match '^[0-9a-f]{8}$') {
        $env:STH_GUID_PREFIX
    } else {
        Write-Warning "STH_GUID_PREFIX must be exactly 8 lowercase hex chars; ignoring '$($env:STH_GUID_PREFIX)'. Using default '$script:DefaultGuidPrefix'."
        $script:DefaultGuidPrefix
    }
} else {
    $script:DefaultGuidPrefix
}

function New-TerminalHereGuid {
    $tail = ([guid]::NewGuid().ToString()).Substring(9) # skip the first 8 hex + '-'
    '{' + $script:GuidPrefix + '-' + $tail + '}'
}

function Test-IsTerminalHereGuid {
    param([string]$Guid)
    if (-not $Guid) { return $false }
    $Guid -like ('{' + $script:GuidPrefix + '-*}')
}

function Get-TerminalSettingsPath {
    <#
    .SYNOPSIS
    Returns the path to the Windows Terminal settings.json on this machine.
    #>
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:SettingsPath)) {
        throw "Windows Terminal settings.json not found at: $script:SettingsPath. Is Windows Terminal installed?"
    }

    $script:SettingsPath
}

function Backup-TerminalSettings {
    <#
    .SYNOPSIS
    Creates a timestamped backup of settings.json next to the original.
    .OUTPUTS
    The full path of the backup file.
    #>
    [CmdletBinding()]
    param()

    $path = Get-TerminalSettingsPath
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = "$path.$stamp.bak"
    Copy-Item -LiteralPath $path -Destination $backup -Force
    $backup
}

function Read-TerminalSettings {
    [CmdletBinding()]
    param()

    $path = Get-TerminalSettingsPath
    $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $raw | ConvertFrom-Json -Depth 64
}

function Write-TerminalSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Settings
    )

    $path = Get-TerminalSettingsPath
    $json = $Settings | ConvertTo-Json -Depth 64
    Set-Content -LiteralPath $path -Value $json -Encoding UTF8
}

function Save-TerminalHere {
    <#
    .SYNOPSIS
    Bookmark the current directory as a new Windows Terminal profile.

    .DESCRIPTION
    Appends a new PowerShell profile to Windows Terminal's settings.json whose
    startingDirectory is the current $PWD. The bookmark appears in the WT
    dropdown immediately (Windows Terminal hot-reloads settings.json).

    Always backs up settings.json before writing.

    .PARAMETER Name
    Display name for the new profile in the dropdown. Required, except when
    `-Claude <session-id>` is given with a non-empty value — then Name
    defaults to the same value so you can write
    `Save-TerminalHere -Claude note-2026` and get a bookmark called
    "note-2026" that resumes Claude session "note-2026".

    .PARAMETER TabColor
    Optional hex colour (e.g. '#1F6FEB') for the tab stripe. Defaults to a
    deterministic colour derived from the Name.

    .PARAMETER ColorScheme
    Colour scheme name to apply. If omitted, no `colorScheme` field is
    written — the profile inherits from `profiles.defaults` in settings.json.
    Pass an explicit scheme name to override.

    .PARAMETER Path
    Directory to bookmark. Defaults to $PWD.

    .PARAMETER Force
    Overwrite an existing bookmark with the same Name without prompting.

    .PARAMETER StartupCommand
    Optional PowerShell command to run when a tab from this bookmark opens.
    Wrapped as `pwsh.exe -NoExit -Command "<cmd>"` so the shell stays alive
    after the command exits. Useful for "this bookmark always opens claude"
    or "always cd in and activate a venv" patterns.

    .PARAMETER Claude
    Make the tab auto-run Claude. Pass an empty string for a fresh session
    (`claude`), or a session ID to resume the latest matching session
    (`claude --continue --resume <id>`, which skips the disambiguation
    picker). Mutually exclusive with -StartupCommand.

    .EXAMPLE
    Save-TerminalHere work
    Bookmarks the current directory under the name "work".

    .EXAMPLE
    Save-TerminalHere -Name "notes" -TabColor "#2EA043"
    Bookmarks $PWD with a green tab.

    .EXAMPLE
    Save-TerminalHere -Name "claude-work" -Claude ""
    Opens a pwsh tab in $PWD and runs `claude`. Shell stays available
    after claude exits.

    .EXAMPLE
    Save-TerminalHere -Name "story-jan-2026" -Claude "xyz-123"
    Opens a pwsh tab and resumes the latest Claude session matching
    xyz-123: `claude --continue --resume xyz-123`.

    .EXAMPLE
    Save-TerminalHere -Claude "note-2026"
    Shorthand. Both the bookmark name and the Claude session ID become
    "note-2026".
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Plain')]
    param(
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'Plain')]
        [Parameter(Mandatory, Position = 0, ParameterSetName = 'WithStartup')]
        [Parameter(Position = 0, ParameterSetName = 'Claude')]
        [AllowEmptyString()]
        [string]$Name,

        [Parameter()]
        [ValidatePattern('^#[0-9A-Fa-f]{6}$')]
        [string]$TabColor,

        [Parameter()]
        [string]$ColorScheme,

        [Parameter()]
        [string]$Path = (Get-Location).Path,

        [Parameter(ParameterSetName = 'WithStartup')]
        [string]$StartupCommand,

        [Parameter(ParameterSetName = 'Claude')]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$Claude,

        [Parameter()]
        [switch]$Force
    )

    if ($PSBoundParameters.ContainsKey('Claude')) {
        # Bare ID (no quotes) — Claude session IDs are slug-shaped. Adding
        # inner quotes would force escaping that Windows command-line
        # tokenization doesn't survive, breaking the resume flow.
        #
        # `--continue --resume <id>` picks the latest session matching <id>
        # without showing the disambiguation picker. Plain `--resume <id>`
        # by itself opens the picker whenever the name is ambiguous.
        $StartupCommand = if ($Claude) {
            'claude --continue --resume ' + $Claude
        } else {
            'claude'
        }
    }

    # Convenience: if -Claude has a value and -Name wasn't supplied, use
    # the Claude session ID as the bookmark name too.
    if (-not $Name) {
        if ($PSCmdlet.ParameterSetName -eq 'Claude' -and $Claude) {
            $Name = $Claude
        } else {
            throw "-Name is required (or pass -Claude with a non-empty session ID)."
        }
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Path is not a directory: $Path"
    }

    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $settings = Read-TerminalSettings

    if (-not $settings.profiles.list) {
        throw 'settings.json has no profiles.list array.'
    }

    $existing = $settings.profiles.list | Where-Object { $_.PSObject.Properties.Name -contains 'name' -and $_.name -eq $Name }
    if ($existing -and -not $Force) {
        throw "A profile named '$Name' already exists. Use -Force to overwrite, or pick a different name."
    }

    if (-not $TabColor) {
        $TabColor = Get-DeterministicTabColor -Seed $Name
    }

    $commandline = if ($StartupCommand) {
        # Pass StartupCommand verbatim inside the outer double-quoted -Command
        # value. Windows command-line tokenization runs first (in WT's spawn),
        # so embedded double quotes in the user's command would need
        # backslash-escaping that PowerShell's source-string syntax doesn't
        # naturally express. Simpler: require the StartupCommand to be
        # quote-free (Claude session IDs are slug-shaped; other commands can
        # be wrapped differently if needed).
        'pwsh.exe -NoExit -Command "' + $StartupCommand + '"'
    } else {
        'pwsh.exe -NoLogo'
    }

    $newGuid = New-TerminalHereGuid
    $newProfile = [ordered]@{
        guid                    = $newGuid
        name                    = $Name
        commandline             = $commandline
        startingDirectory       = $resolved
        tabColor                = $TabColor
        icon                    = 'ms-appx:///ProfileIcons/{574e775e-4f2a-5b96-ac1e-a2962a402336}.png'
        suppressApplicationTitle = $true
        tabTitle                = $Name
        hidden                  = $false
    }
    if ($ColorScheme) { $newProfile['colorScheme'] = $ColorScheme }

    if ($PSCmdlet.ShouldProcess($script:SettingsPath, "Add bookmark '$Name' -> $resolved")) {
        $backup = Backup-TerminalSettings
        Write-Verbose "Backup written to: $backup"

        if ($existing) {
            $settings.profiles.list = @($settings.profiles.list | Where-Object { $_.name -ne $Name })
        }
        $settings.profiles.list = @($newProfile) + @($settings.profiles.list)

        Write-TerminalSettings -Settings $settings
        [pscustomobject]@{
            Name              = $Name
            StartingDirectory = $resolved
            TabColor          = $TabColor
            ColorScheme       = if ($ColorScheme) { $ColorScheme } else { '(inherited)' }
            StartupCommand    = $StartupCommand
            Guid              = $newGuid
            BackupPath        = $backup
        }
    }
}

function Get-TerminalHere {
    <#
    .SYNOPSIS
    Lists bookmarks created by Save-TerminalHere.

    .DESCRIPTION
    Returns profile entries that look like Save-TerminalHere bookmarks
    (commandline 'pwsh.exe -NoLogo' with a startingDirectory set).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name = '*'
    )

    $settings = Read-TerminalSettings
    $settings.profiles.list |
        Where-Object {
            $_.PSObject.Properties.Name -contains 'guid' -and
            (Test-IsTerminalHereGuid -Guid $_.guid)
        } |
        Where-Object { $_.name -like $Name } |
        ForEach-Object {
            $startup = $null
            if ($_.commandline -match '-Command\s+"(.*)"$') {
                $startup = $Matches[1] -replace '`"', '"'
            }
            [pscustomobject]@{
                Name              = $_.name
                StartingDirectory = $_.startingDirectory
                TabColor          = ($_.PSObject.Properties.Name -contains 'tabColor') ? $_.tabColor : $null
                ColorScheme       = ($_.PSObject.Properties.Name -contains 'colorScheme') ? $_.colorScheme : $null
                StartupCommand    = $startup
                Guid              = $_.guid
            }
        }
}

function Remove-TerminalHere {
    <#
    .SYNOPSIS
    Remove a bookmark by Name.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [string]$Name
    )

    process {
        $settings = Read-TerminalSettings
        $match = $settings.profiles.list | Where-Object {
            $_.name -eq $Name -and (Test-IsTerminalHereGuid -Guid $_.guid)
        }
        if (-not $match) {
            Write-Warning "No Save-TerminalHere bookmark named '$Name' found. (Profiles created outside this module aren't touched.)"
            return
        }

        if ($PSCmdlet.ShouldProcess($script:SettingsPath, "Remove bookmark '$Name'")) {
            $backup = Backup-TerminalSettings
            Write-Verbose "Backup written to: $backup"
            $matchGuid = $match.guid
            $settings.profiles.list = @($settings.profiles.list | Where-Object { $_.guid -ne $matchGuid })
            Write-TerminalSettings -Settings $settings
            [pscustomobject]@{ Name = $Name; Removed = $true; BackupPath = $backup }
        }
    }
}

function Rename-TerminalHere {
    <#
    .SYNOPSIS
    Rename an existing bookmark in place.

    .DESCRIPTION
    Updates the `name` (and matching `tabTitle`) of an existing profile in
    settings.json without changing its GUID or any other field. Preserves
    colour, starting directory, icon — everything except the label.

    .PARAMETER Name
    Current name of the bookmark.

    .PARAMETER NewName
    The new name.

    .EXAMPLE
    Rename-TerminalHere foo bar
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$NewName
    )

    process {
        if ($Name -eq $NewName) {
            Write-Warning "Name and NewName are identical; nothing to do."
            return
        }

        $settings = Read-TerminalSettings
        $target = $settings.profiles.list | Where-Object {
            $_.name -eq $Name -and (Test-IsTerminalHereGuid -Guid $_.guid)
        }
        if (-not $target) {
            Write-Warning "No Save-TerminalHere bookmark named '$Name' found. (Profiles created outside this module aren't touched.)"
            return
        }

        $collision = $settings.profiles.list | Where-Object { $_.name -eq $NewName }
        if ($collision) {
            throw "A profile named '$NewName' already exists. Pick a different name or remove the existing one first."
        }

        if ($PSCmdlet.ShouldProcess($script:SettingsPath, "Rename bookmark '$Name' -> '$NewName'")) {
            $backup = Backup-TerminalSettings
            Write-Verbose "Backup written to: $backup"

            $target.name = $NewName
            if ($target.PSObject.Properties.Name -contains 'tabTitle') {
                $target.tabTitle = $NewName
            } else {
                $target | Add-Member -NotePropertyName 'tabTitle' -NotePropertyValue $NewName
            }

            Write-TerminalSettings -Settings $settings
            [pscustomobject]@{
                OldName    = $Name
                NewName    = $NewName
                BackupPath = $backup
            }
        }
    }
}

function Install-SaveTerminalHere {
    <#
    .SYNOPSIS
    Wire Save-TerminalHere into your PowerShell $PROFILE so it autoloads in
    every new shell.

    .DESCRIPTION
    Idempotently appends an Import-Module line to $PROFILE. Creates the
    profile file if it doesn't exist. Detects whether the module lives on
    $env:PSModulePath (writes `Import-Module Save-TerminalHere`) or in an
    arbitrary clone location (writes the absolute path to the .psd1).

    Re-runnable safely — if the import line is already present, it does
    nothing.

    .EXAMPLE
    Install-SaveTerminalHere
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $moduleBase = $script:PSScriptRoot
    if (-not $moduleBase) {
        $moduleBase = $MyInvocation.MyCommand.Module.ModuleBase
    }

    $onPSModulePath = $false
    foreach ($p in $env:PSModulePath -split [System.IO.Path]::PathSeparator) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($moduleBase -like (Join-Path $p '*')) { $onPSModulePath = $true; break }
    }

    $importLine = if ($onPSModulePath) {
        'Import-Module Save-TerminalHere'
    } else {
        $psd1 = Join-Path $moduleBase 'Save-TerminalHere.psd1'
        "Import-Module '$psd1'"
    }

    # Target the per-host profile ($PROFILE === CurrentUserCurrentHost),
    # which is where pwsh users (and tools like PowerToys) wire imports.
    # AllHosts (profile.ps1) is for ISE/embed compat we don't need.
    $profilePath = $PROFILE

    $alreadyInstalled = $false
    if (Test-Path -LiteralPath $profilePath) {
        $existing = Get-Content -LiteralPath $profilePath -Raw -ErrorAction SilentlyContinue
        if ($existing) {
            $needle = if ($onPSModulePath) {
                'Import-Module\s+(?:''|")?Save-TerminalHere(?:''|")?'
            } else {
                'Import-Module\s+(?:''|")?' + [regex]::Escape((Join-Path $moduleBase 'Save-TerminalHere.psd1')) + '(?:''|")?'
            }
            if ($existing -match $needle) { $alreadyInstalled = $true }
        }
    }

    $action = if ($alreadyInstalled) { 'AlreadyInstalled' } else { 'Installed' }

    if (-not $alreadyInstalled) {
        if ($PSCmdlet.ShouldProcess($profilePath, "Append: $importLine")) {
            if (-not (Test-Path -LiteralPath $profilePath)) {
                New-Item -ItemType File -Path $profilePath -Force | Out-Null
            }
            $block = "`n# Save-TerminalHere bookmark module`n$importLine`n"
            Add-Content -LiteralPath $profilePath -Value $block
        }
    }

    [pscustomobject]@{
        ProfilePath = $profilePath
        Action      = $action
        ImportLine  = $importLine
    }
}

function Set-TerminalHereColor {
    <#
    .SYNOPSIS
    Change the tab colour of an existing bookmark without touching other fields.

    .DESCRIPTION
    Use this after you've experimented with a tab colour via right-click → Color
    on a live Windows Terminal tab. The picker doesn't persist; pass the hex
    you settled on here and it gets written into the saved profile.

    .PARAMETER Name
    Name of the bookmark to update. Required.

    .PARAMETER TabColor
    Hex colour, e.g. '#1F6FEB'. Required.

    .EXAMPLE
    Set-TerminalHereColor work "#1F6FEB"
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [ValidatePattern('^#[0-9A-Fa-f]{6}$')]
        [string]$TabColor
    )

    process {
        $settings = Read-TerminalSettings
        $target = $settings.profiles.list | Where-Object {
            $_.name -eq $Name -and (Test-IsTerminalHereGuid -Guid $_.guid)
        }
        if (-not $target) {
            Write-Warning "No Save-TerminalHere bookmark named '$Name' found. (Profiles created outside this module aren't touched.)"
            return
        }

        if ($PSCmdlet.ShouldProcess($script:SettingsPath, "Set tabColor of '$Name' to $TabColor")) {
            $backup = Backup-TerminalSettings
            Write-Verbose "Backup written to: $backup"

            if ($target.PSObject.Properties.Name -contains 'tabColor') {
                $target.tabColor = $TabColor
            } else {
                $target | Add-Member -NotePropertyName 'tabColor' -NotePropertyValue $TabColor
            }

            Write-TerminalSettings -Settings $settings
            [pscustomobject]@{
                Name       = $Name
                TabColor   = $TabColor
                BackupPath = $backup
            }
        }
    }
}

function ConvertTo-PortablePath {
    <#
    .SYNOPSIS
    Replace machine-specific path prefixes with environment-variable references
    so the path stays meaningful when imported on another machine.
    #>
    param([string]$Path)

    if (-not $Path) { return $Path }

    # Longest-prefix-first so OneDrive paths inside USERPROFILE map correctly.
    $map = @(
        @{ Env = 'OneDriveCommercial'; Value = $env:OneDriveCommercial }
        @{ Env = 'OneDriveConsumer';   Value = $env:OneDriveConsumer }
        @{ Env = 'OneDrive';           Value = $env:OneDrive }
        @{ Env = 'USERPROFILE';        Value = $env:USERPROFILE }
    ) | Where-Object { $_.Value }

    $map = $map | Sort-Object -Property @{ Expression = { $_.Value.Length }; Descending = $true }

    foreach ($entry in $map) {
        if ($Path.StartsWith($entry.Value, [System.StringComparison]::OrdinalIgnoreCase)) {
            return '%' + $entry.Env + '%' + $Path.Substring($entry.Value.Length)
        }
    }

    $Path
}

function Export-TerminalHere {
    <#
    .SYNOPSIS
    Export bookmarks as a Windows Terminal Fragment JSON file, portable across
    machines.

    .DESCRIPTION
    Reads matching bookmarks from settings.json and emits a Fragment-shaped
    JSON file. Machine-specific bits are stripped or normalised:
      - GUIDs removed (Windows Terminal regenerates on import)
      - startingDirectory paths rewritten with %USERPROFILE%, %OneDrive% etc.

    Use Import-TerminalHere on another machine to install the fragment.

    .PARAMETER Name
    Wildcard filter on bookmark name. Default '*' (all).

    .PARAMETER Path
    Output file path. If omitted, defaults to a timestamped, machine-tagged
    file on your Desktop:
    `~\Desktop\save-terminal-here-<COMPUTERNAME>-<yyyyMMdd-HHmmss>.json`.
    The COMPUTERNAME tag makes it obvious which machine the bookmarks came
    from when shuttling files between PCs.

    .PARAMETER IncludeSchemes
    Also include the colour schemes referenced by exported profiles, so the
    target machine doesn't need them pre-defined.

    .EXAMPLE
    Export-TerminalHere
    # Writes to e.g. ~\Desktop\save-terminal-here-DESKTOP-AB12CD3-20260526-081650.json

    .EXAMPLE
    Export-TerminalHere -Path .\my-terminals.json -IncludeSchemes
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Name = '*',

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$IncludeSchemes
    )

    if (-not $Path) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $pc = $env:COMPUTERNAME
        $Path = Join-Path ([Environment]::GetFolderPath('Desktop')) "save-terminal-here-$pc-$stamp.json"
    }

    $settings = Read-TerminalSettings

    $matching = $settings.profiles.list | Where-Object {
        $_.PSObject.Properties.Name -contains 'guid' -and
        (Test-IsTerminalHereGuid -Guid $_.guid) -and
        $_.name -like $Name
    }

    if (-not $matching) {
        Write-Warning "No bookmarks matched name '$Name'."
        return
    }

    $profiles = @()
    $schemeNames = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($p in $matching) {
        # Keep the prefix-tagged guid in the fragment so the marker survives
        # cross-machine. WT respects guids supplied in fragment profiles.
        $clean = [ordered]@{
            guid              = $p.guid
            name              = $p.name
            commandline       = $p.commandline
            startingDirectory = ConvertTo-PortablePath -Path $p.startingDirectory
        }
        foreach ($field in 'colorScheme', 'tabColor', 'icon', 'suppressApplicationTitle', 'tabTitle', 'hidden') {
            if ($p.PSObject.Properties.Name -contains $field) {
                $clean[$field] = $p.$field
                if ($field -eq 'colorScheme' -and $p.colorScheme) {
                    [void]$schemeNames.Add($p.colorScheme)
                }
            }
        }
        $profiles += $clean
    }

    $fragment = [ordered]@{ profiles = $profiles }

    if ($IncludeSchemes -and $schemeNames.Count -gt 0 -and $settings.schemes) {
        $schemes = $settings.schemes | Where-Object { $_.name -and $schemeNames.Contains($_.name) }
        if ($schemes) {
            $fragment['schemes'] = @($schemes)
        }
    }

    $json = $fragment | ConvertTo-Json -Depth 64
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8

    [pscustomobject]@{
        Path           = (Resolve-Path -LiteralPath $Path).Path
        ProfileCount   = $profiles.Count
        SchemeCount    = if ($fragment.Contains('schemes')) { $fragment.schemes.Count } else { 0 }
    }
}

function Import-TerminalHere {
    <#
    .SYNOPSIS
    Install a Save-TerminalHere fragment exported from another machine.

    .DESCRIPTION
    Default mode 'Fragment' (recommended): copies the JSON into
    %LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\<FragmentName>\
    where Windows Terminal auto-merges it without touching settings.json.

    Mode 'Merge': appends the fragment's profiles and schemes directly into
    settings.json. Destructive (writes settings.json) but means the imported
    bookmarks survive a fragments-folder wipe.

    .PARAMETER Path
    Path to a fragment JSON produced by Export-TerminalHere.

    .PARAMETER Mode
    'Fragment' (default) or 'Merge'.

    .PARAMETER FragmentName
    Name of the subfolder under Fragments\. Default 'Save-TerminalHere'.

    .EXAMPLE
    Import-TerminalHere .\my-terminals.json

    .EXAMPLE
    Import-TerminalHere .\my-terminals.json -Mode Merge
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Fragment', 'Merge')]
        [string]$Mode = 'Fragment',

        [Parameter()]
        [string]$FragmentName = 'Save-TerminalHere'
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Fragment file not found: $Path"
    }

    $fragment = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 64
    if (-not $fragment.profiles) {
        throw "No 'profiles' array in fragment file: $Path"
    }

    if ($Mode -eq 'Fragment') {
        $fragmentsRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments'
        $targetDir = Join-Path $fragmentsRoot $FragmentName
        $targetFile = Join-Path $targetDir 'bookmarks.json'

        # Retag any incoming GUID whose prefix doesn't match this machine's
        # configured prefix, so imported bookmarks are recognised by local
        # Get-/Rename-/Set-/Remove-TerminalHere cmdlets.
        $retagged = 0
        foreach ($p in $fragment.profiles) {
            $existing = if ($p.PSObject.Properties.Name -contains 'guid') { $p.guid } else { $null }
            if (-not (Test-IsTerminalHereGuid -Guid $existing)) {
                $newGuid = New-TerminalHereGuid
                if ($p.PSObject.Properties.Name -contains 'guid') {
                    $p.guid = $newGuid
                } else {
                    $p | Add-Member -NotePropertyName 'guid' -NotePropertyValue $newGuid
                }
                $retagged++
            }
        }

        if ($PSCmdlet.ShouldProcess($targetFile, 'Install Windows Terminal fragment')) {
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            $fragment | ConvertTo-Json -Depth 64 | Set-Content -LiteralPath $targetFile -Encoding UTF8

            $hasSchemes = $fragment.PSObject.Properties.Name -contains 'schemes'
            $schemeCount = if ($hasSchemes -and $fragment.schemes) { @($fragment.schemes).Count } else { 0 }

            [pscustomobject]@{
                Mode           = 'Fragment'
                Installed      = $targetFile
                ProfileCount   = @($fragment.profiles).Count
                SchemeCount    = $schemeCount
                GuidsRetagged  = $retagged
                LocalPrefix    = $script:GuidPrefix
                Hint           = 'Close and reopen Windows Terminal to load the fragment.'
            }
        }
        return
    }

    # Merge mode: read settings.json, append profiles/schemes, write back.
    $settings = Read-TerminalSettings
    $existingNames = @($settings.profiles.list | ForEach-Object { $_.name })
    $existingSchemes = if ($settings.schemes) { @($settings.schemes | ForEach-Object { $_.name }) } else { @() }

    $added = 0
    $skipped = 0
    foreach ($p in $fragment.profiles) {
        if ($existingNames -contains $p.name) {
            Write-Warning "Skipping '$($p.name)' — a profile with this name already exists."
            $skipped++
            continue
        }
        # Preserve a prefix-tagged guid if the fragment carried one; otherwise
        # mint a new one with our prefix so the bookmark is recognisable here.
        $fragGuid = if ($p.PSObject.Properties.Name -contains 'guid') { $p.guid } else { $null }
        $guid = if (Test-IsTerminalHereGuid -Guid $fragGuid) { $fragGuid } else { New-TerminalHereGuid }
        $obj = [ordered]@{ guid = $guid }
        foreach ($prop in $p.PSObject.Properties) {
            if ($prop.Name -eq 'guid') { continue }
            $obj[$prop.Name] = $prop.Value
        }
        $settings.profiles.list = @($obj) + @($settings.profiles.list)
        $added++
    }

    $schemesAdded = 0
    $hasSchemes = $fragment.PSObject.Properties.Name -contains 'schemes'
    if ($hasSchemes -and $fragment.schemes) {
        foreach ($s in $fragment.schemes) {
            if ($existingSchemes -contains $s.name) { continue }
            if (-not ($settings.PSObject.Properties.Name -contains 'schemes') -or -not $settings.schemes) {
                $settings | Add-Member -NotePropertyName 'schemes' -NotePropertyValue @() -Force
            }
            $settings.schemes = @($settings.schemes) + @($s)
            $schemesAdded++
        }
    }

    if ($PSCmdlet.ShouldProcess($script:SettingsPath, "Merge fragment: +$added profiles, +$schemesAdded schemes")) {
        $backup = Backup-TerminalSettings
        Write-Verbose "Backup written to: $backup"
        Write-TerminalSettings -Settings $settings

        [pscustomobject]@{
            Mode            = 'Merge'
            ProfilesAdded   = $added
            ProfilesSkipped = $skipped
            SchemesAdded    = $schemesAdded
            BackupPath      = $backup
        }
    }
}

function Get-DeterministicTabColor {
    param(
        [Parameter(Mandatory)]
        [string]$Seed
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Seed)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = $sha.ComputeHash($bytes)
    } finally {
        $sha.Dispose()
    }

    $palette = @(
        '#1F6FEB', '#2EA043', '#D29922', '#A371F7', '#F778BA',
        '#E3B341', '#56D364', '#79C0FF', '#FF7B72', '#D2A8FF'
    )
    $palette[$hash[0] % $palette.Count]
}

Export-ModuleMember -Function Save-TerminalHere, Get-TerminalHere, Remove-TerminalHere, Set-TerminalHereColor, Rename-TerminalHere, Install-SaveTerminalHere, Export-TerminalHere, Import-TerminalHere
