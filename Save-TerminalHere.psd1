@{
    RootModule        = 'Save-TerminalHere.psm1'
    ModuleVersion     = '0.7.1'
    GUID              = 'c4d2f8a1-7b3e-4d92-9a5c-1e6b8f4d2a37'
    Author            = 'Julian Snowden'
    CompanyName       = 'Unknown'
    Copyright         = '(c) Julian Snowden. All rights reserved.'
    Description       = 'Bookmark the current PowerShell directory as a new Windows Terminal profile, so the next time you open the dropdown the location is one click away.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @('Save-TerminalHere', 'Get-TerminalHere', 'Remove-TerminalHere', 'Set-TerminalHereColor', 'Rename-TerminalHere', 'Install-SaveTerminalHere', 'Export-TerminalHere', 'Import-TerminalHere')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags         = @('WindowsTerminal', 'Profile', 'Bookmark', 'Productivity')
            LicenseUri   = 'https://github.com/snowdej/Save-TerminalHere/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/snowdej/Save-TerminalHere'
            ReleaseNotes = '0.7.1 - install.ps1 now echoes the installed version and a richer quick-reference: bookmark current dir, bookmark with tab colour, fresh Claude, resume Claude (name-defaults-to-id), browse/rename/delete, export/import. No behaviour changes in the module itself.'
        }
    }
}
