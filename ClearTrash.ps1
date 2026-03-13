try {
    $rawUI = $Host.UI.RawUI

    $width = 82
    $height = 24
    $bufferHeight = 800

    if ($rawUI.BufferSize.Width -lt $width) {
        $rawUI.BufferSize = New-Object Management.Automation.Host.Size($width, $rawUI.BufferSize.Height)
    }

    $rawUI.WindowSize = New-Object Management.Automation.Host.Size($width, $height)
    $rawUI.BufferSize = New-Object Management.Automation.Host.Size($width, $bufferHeight)
}
catch {
}

$githubUrl = "https://github.com/MrcVnz"
$cleanMode = 1

$scriptRoot = if ($PSScriptRoot) {
    $PSScriptRoot
}
elseif ($MyInvocation.MyCommand.Path) {
    Split-Path -Parent $MyInvocation.MyCommand.Path
}
else {
    (Get-Location).Path
}

$configFilePath = Join-Path $scriptRoot "ClearTrash.config.json"
$defaultLogFolder = Join-Path $scriptRoot "ClearTrashLogs"

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Header {
    Clear-Host

    if ($script:useUnicode) {
        Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                  CLEARTRASH                  ║" -ForegroundColor Cyan
        Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
    }
    else {
        Write-Host "==============================================" -ForegroundColor Cyan
        Write-Host "                  CLEARTRASH                  " -ForegroundColor Cyan
        Write-Host "==============================================" -ForegroundColor Cyan
    }

    Write-Host ""
}

function Get-ModeText {
    switch ($cleanMode) {
        1 { "Recycle Bin" }
        2 { "Permanent Delete" }
        3 { "Recycle Bin + Empty Bin" }
        default { "Unknown" }
    }
}

function Format-Size($bytes) {
    if ($null -eq $bytes -or $bytes -lt 0) {
        $bytes = 0
    }

    if ($bytes -ge 1TB) { return "{0:N2} TB" -f ($bytes / 1TB) }
    if ($bytes -ge 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -ge 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -ge 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }

    return "$bytes B"
}

function Get-DateTimeValue($value) {
    if ($value -is [datetime]) {
        return $value
    }

    if ($null -eq $value) {
        return (Get-Date)
    }

    try {
        return [datetime]$value
    }
    catch {
        return (Get-Date)
    }
}

function Add-DetailEntry {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Value
    )

    if ($null -eq $List -or [string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    if ($List.Count -lt $script:maxDetailedEntries) {
        $List.Add($Value)
    }
}

function Get-ProgressGlyph {
    param([bool]$Filled)

    if ($script:useUnicode) {
        if ($Filled) { return "█" }
        return "░"
    }

    if ($Filled) { return "#" }
    return "-"
}

function Resolve-ConfiguredPath {
    param(
        [string]$PathValue,
        [string]$Fallback
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $Fallback
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($PathValue.Trim())

    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return $expanded
    }

    if ($expanded.StartsWith(".\")) {
        $expanded = $expanded.Substring(2)
    }
    elseif ($expanded.StartsWith("./")) {
        $expanded = $expanded.Substring(2)
    }

    return (Join-Path $scriptRoot $expanded)
}

function Get-DefaultConfig {
    return [ordered]@{
        defaultLogFolder       = ".\ClearTrashLogs"
        retryCount             = 1
        retryDelayMs           = 200
        disabledDefaultTargets = @()
        maxDetailedEntries     = 5000
        writeJsonLog           = $true
        requireConfirmation    = $true
        previewFullLog         = $true
        previewSampleLimit     = 15
        customTargets          = @()
        useUnicode             = $true
    }
}

function Save-Config {
    param([hashtable]$Config)

    try {
        $json = $Config | ConvertTo-Json -Depth 6
        Set-Content -LiteralPath $configFilePath -Value $json -Encoding UTF8
        return $true
    }
    catch {
        return $false
    }
}

function Load-Config {
    $config = Get-DefaultConfig

    if (!(Test-Path -LiteralPath $configFilePath)) {
        Save-Config $config | Out-Null
        return $config
    }

    try {
        $raw = Get-Content -LiteralPath $configFilePath -Raw -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $config
        }

        $loaded = $raw | ConvertFrom-Json -ErrorAction Stop

        if ($null -ne $loaded.disabledDefaultTargets) {
            $config.disabledDefaultTargets = @($loaded.disabledDefaultTargets)
        }

        if ($null -ne $loaded.customTargets) {
            $config.customTargets = @($loaded.customTargets)
        }

        if ($null -ne $loaded.previewSampleLimit) {
            $limit = 0
            if ([int]::TryParse([string]$loaded.previewSampleLimit, [ref]$limit)) {
                if ($limit -gt 0) {
                    $config.previewSampleLimit = $limit
                }
            }
        }

        if ($null -ne $loaded.previewFullLog) {
            $config.previewFullLog = [bool]$loaded.previewFullLog
        }

        if ($null -ne $loaded.defaultLogFolder -and -not [string]::IsNullOrWhiteSpace([string]$loaded.defaultLogFolder)) {
            $config.defaultLogFolder = [string]$loaded.defaultLogFolder
        }

        if ($null -ne $loaded.retryCount) {
            $value = 0
            if ([int]::TryParse([string]$loaded.retryCount, [ref]$value) -and $value -ge 0) {
                $config.retryCount = $value
            }
        }

        if ($null -ne $loaded.retryDelayMs) {
            $value = 0
            if ([int]::TryParse([string]$loaded.retryDelayMs, [ref]$value) -and $value -ge 0) {
                $config.retryDelayMs = $value
            }
        }

        if ($null -ne $loaded.maxDetailedEntries) {
            $value = 0
            if ([int]::TryParse([string]$loaded.maxDetailedEntries, [ref]$value) -and $value -gt 0) {
                $config.maxDetailedEntries = $value
            }
        }

        if ($null -ne $loaded.writeJsonLog) {
            $config.writeJsonLog = [bool]$loaded.writeJsonLog
        }

        if ($null -ne $loaded.requireConfirmation) {
            $config.requireConfirmation = [bool]$loaded.requireConfirmation
        }

        if ($null -ne $loaded.useUnicode) {
            $config.useUnicode = [bool]$loaded.useUnicode
        }

        return $config
    }
    catch {
        return $config
    }
}

function Get-DefaultTargets {
    return @(
        @{ Name = "User TEMP"; Path = $env:TEMP; Source = "Default" },
        @{ Name = "Windows TEMP"; Path = "C:\Windows\Temp"; Source = "Default" },
        @{ Name = "Prefetch"; Path = "C:\Windows\Prefetch"; Source = "Default" },
        @{ Name = "DirectX Shader Cache"; Path = "$env:LOCALAPPDATA\D3DSCache"; Source = "Default" },
        @{ Name = "Thumbnail Cache"; Path = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"; Source = "Default" },
        @{ Name = "WER ReportQueue"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportQueue"; Source = "Default" },
        @{ Name = "WER ReportArchive"; Path = "$env:ProgramData\Microsoft\Windows\WER\ReportArchive"; Source = "Default" },
        @{ Name = "Crash Dumps"; Path = "C:\Windows\Minidump"; Source = "Default" },
        @{ Name = "Local Crash Dumps"; Path = "$env:LOCALAPPDATA\CrashDumps"; Source = "Default" },
        @{ Name = "Windows Update Download"; Path = "C:\Windows\SoftwareDistribution\Download"; Source = "Default" },
        @{ Name = "Delivery Optimization Cache"; Path = "C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"; Source = "Default" },
        @{ Name = "Windows Defender Cache"; Path = "C:\ProgramData\Microsoft\Windows Defender\Scans\History"; Source = "Default" }
    )
}

function Get-EffectiveTargets {
    param([hashtable]$Config)

    $targets = New-Object System.Collections.Generic.List[object]
    $disabled = @()

    if ($Config.disabledDefaultTargets) {
        $disabled = @($Config.disabledDefaultTargets | ForEach-Object { [string]$_ })
    }

    foreach ($target in (Get-DefaultTargets)) {
        if ($disabled -contains $target.Name) {
            continue
        }

        $resolvedPath = Resolve-ConfiguredPath -PathValue $target.Path -Fallback $target.Path
        $targets.Add([pscustomobject]@{
            Name   = $target.Name
            Path   = $resolvedPath
            Source = $target.Source
        })
    }

    foreach ($custom in @($Config.customTargets)) {
        if ($null -eq $custom) {
            continue
        }

        $enabled = $true
        if ($null -ne $custom.enabled) {
            $enabled = [bool]$custom.enabled
        }

        if (-not $enabled) {
            continue
        }

        $name = [string]$custom.name
        $path = [string]$custom.path

        if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        $resolvedPath = Resolve-ConfiguredPath -PathValue $path -Fallback $path
        $targets.Add([pscustomobject]@{
            Name   = $name
            Path   = $resolvedPath
            Source = "Custom"
        })
    }

    $withKeys = @()
    for ($i = 0; $i -lt $targets.Count; $i++) {
        $withKeys += [pscustomobject]@{
            Key    = [string]($i + 1)
            Name   = $targets[$i].Name
            Path   = $targets[$i].Path
            Source = $targets[$i].Source
        }
    }

    return $withKeys
}

function Refresh-Settings {
    $script:appConfig = Load-Config
    $script:previewSampleLimit = $script:appConfig.previewSampleLimit
    $script:previewFullLog = [bool]$script:appConfig.previewFullLog
    $script:retryCount = [int]$script:appConfig.retryCount
    $script:retryDelayMs = [int]$script:appConfig.retryDelayMs
    $script:maxDetailedEntries = [int]$script:appConfig.maxDetailedEntries
    $script:writeJsonLog = [bool]$script:appConfig.writeJsonLog
    $script:requireConfirmation = [bool]$script:appConfig.requireConfirmation
    $script:useUnicode = [bool]$script:appConfig.useUnicode
    $script:defaultLogFolder = Resolve-ConfiguredPath -PathValue $script:appConfig.defaultLogFolder -Fallback (Join-Path $scriptRoot "ClearTrashLogs")
    $legacyLogFolder = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "ClearTrashLogs"

    if ([string]::Equals($script:defaultLogFolder, $legacyLogFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
        $script:defaultLogFolder = Join-Path $scriptRoot "ClearTrashLogs"
    }

    $script:targets = Get-EffectiveTargets -Config $script:appConfig
}

function Get-Target($key) {
    return $script:targets | Where-Object { $_.Key -eq $key } | Select-Object -First 1
}

function Get-FolderSize($path) {
    if (!(Test-Path -LiteralPath $path)) {
        return 0
    }

    try {
        $sum = (Get-ChildItem -LiteralPath $path -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [int64]$sum
    }
    catch {
        return 0
    }
}

function Get-ItemSize($item) {
    try {
        if (-not $item.PSIsContainer) {
            if ($null -ne $item.Length) {
                return [int64]$item.Length
            }

            return 0
        }

        $sum = (Get-ChildItem -LiteralPath $item.FullName -Force -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        if ($null -eq $sum) { return 0 }
        return [int64]$sum
    }
    catch {
        return 0
    }
}

function Show-MainMenu {
    Refresh-Settings
    Show-Header

    Write-Host "Mode: " -NoNewline
    switch ($cleanMode) {
        1 { Write-Host "Recycle Bin" -ForegroundColor Green }
        2 { Write-Host "Permanent Delete" -ForegroundColor Yellow }
        3 { Write-Host "Recycle + Empty Bin" -ForegroundColor Magenta }
    }

    Write-Host ""
    Write-Host "[1] Start cleaning" -ForegroundColor White
    Write-Host "[2] Change mode" -ForegroundColor White
    Write-Host "[3] Preview mode (scan only)" -ForegroundColor White
    Write-Host "[4] Open config folder" -ForegroundColor White
    Write-Host "[5] Creator GitHub" -ForegroundColor White
    Write-Host "[6] Exit" -ForegroundColor White
    Write-Host ""
}

function Show-ProgressBar($current, $total) {
    if ($total -le 0) {
        return
    }

    $percent = [math]::Floor(($current / $total) * 100)
    $width = 24
    $filled = [math]::Floor(($percent / 100) * $width)

    $bar = ""
    for ($i = 0; $i -lt $width; $i++) {
        $bar += Get-ProgressGlyph ($i -lt $filled)
    }

    $line = "[{0}] {1,3}%  {2}/{3}" -f $bar, $percent, $current, $total

    Write-Host -NoNewline "`r$line"
}

function Select-Folders {
    Refresh-Settings
    Show-Header

    Write-Host "Choose what to clean" -ForegroundColor Yellow
    Write-Host "────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    if (!$script:targets -or $script:targets.Count -eq 0) {
        Write-Host "No cleanup targets are available." -ForegroundColor Red
        Write-Host ""
        Pause
        return @()
    }

    foreach ($target in $script:targets) {
        $existsText = if (Test-Path -LiteralPath $target.Path) { "" } else { " (not found)" }
        $sourceText = if ($target.Source -eq "Custom") { " [custom]" } else { "" }
        Write-Host ("[{0}] {1}{2}{3}" -f $target.Key, $target.Name, $sourceText, $existsText)
    }

    Write-Host ""
    Write-Host "Type: 1   or   1,2   or   all" -ForegroundColor DarkGray
    Write-Host ""

    $inputValue = Read-Host "Selection"

    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return @()
    }

    if ($inputValue.Trim().ToLower() -eq "all") {
        return @($script:targets.Key)
    }

    $selected = @()

    foreach ($part in ($inputValue -split ",")) {
        $key = $part.Trim()
        if ($script:targets.Key -contains $key -and $selected -notcontains $key) {
            $selected += $key
        }
    }

    return $selected
}

function Change-Mode {
    Show-Header

    Write-Host "Cleaning mode" -ForegroundColor Yellow
    Write-Host "─────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "[1] Send to Recycle Bin"
    Write-Host "[2] Permanent Delete"
    Write-Host "[3] Recycle + Empty Bin"
    Write-Host ""

    $choice = Read-Host "Select mode"

    switch ($choice) {
        "1" { $script:cleanMode = 1 }
        "2" { $script:cleanMode = 2 }
        "3" { $script:cleanMode = 3 }
        default {
            Write-Host ""
            Write-Host "Invalid option." -ForegroundColor Red
            Start-Sleep 1
        }
    }
}

function Ask-LogSettings {
    $result = @{
        Enabled = $false
        Folder  = ""
    }

    Write-Host ""
    $saveLog = Read-Host "Do you want to save a log? (Y/N)"

    if ($saveLog -notmatch '^(?i)y(es)?$') {
        return $result
    }

    while ($true) {
        Show-Header
        Write-Host "Log options" -ForegroundColor Yellow
        Write-Host "───────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "[1] Default"
        Write-Host ("    Save in: {0}" -f $script:defaultLogFolder) -ForegroundColor DarkGray
        Write-Host "[2] Custom path"
        Write-Host "    Example: C:\Users\YourName\Documents\ClearTrashLogs" -ForegroundColor DarkGray
        Write-Host "[0] Cancel log"
        Write-Host ""

        $choice = Read-Host "Select option"

        switch ($choice) {
            "1" {
                try {
                    if (!(Test-Path -LiteralPath $script:defaultLogFolder)) {
                        New-Item -ItemType Directory -Path $script:defaultLogFolder -Force | Out-Null
                    }

                    if (Test-Path -LiteralPath $script:defaultLogFolder -PathType Container) {
                        $result.Enabled = $true
                        $result.Folder = $script:defaultLogFolder
                        return $result
                    }

                    Write-Host ""
                    Write-Host "Could not use the default log folder." -ForegroundColor Red
                    Start-Sleep 1
                }
                catch {
                    Write-Host ""
                    Write-Host "Could not create the default log folder." -ForegroundColor Red
                    Start-Sleep 1
                }
            }

            "2" {
                while ($true) {
                    Show-Header
                    Write-Host "Custom log path" -ForegroundColor Yellow
                    Write-Host "───────────────" -ForegroundColor DarkGray
                    Write-Host ""
                    Write-Host "Enter the full folder path." -ForegroundColor White
                    Write-Host "Example: C:\Users\YourName\Documents\ClearTrashLogs" -ForegroundColor DarkGray
                    Write-Host ""

                    $folder = Read-Host "Custom log folder (type 0 to go back)"

                    if ($folder -eq "0") {
                        break
                    }

                    if ([string]::IsNullOrWhiteSpace($folder)) {
                        Write-Host ""
                        Write-Host "Invalid folder." -ForegroundColor Red
                        Start-Sleep 1
                        continue
                    }

                    $resolvedFolder = Resolve-ConfiguredPath -PathValue $folder -Fallback $folder

                    if (!(Test-Path -LiteralPath $resolvedFolder)) {
                        $create = Read-Host "Folder does not exist. Create it? (Y/N)"
                        if ($create -match '^(?i)y(es)?$') {
                            try {
                                New-Item -ItemType Directory -Path $resolvedFolder -Force | Out-Null
                            }
                            catch {
                                Write-Host ""
                                Write-Host "Could not create folder." -ForegroundColor Red
                                Start-Sleep 1
                                continue
                            }
                        }
                        else {
                            continue
                        }
                    }

                    if (Test-Path -LiteralPath $resolvedFolder -PathType Container) {
                        $result.Enabled = $true
                        $result.Folder = $resolvedFolder
                        return $result
                    }

                    Write-Host ""
                    Write-Host "Invalid folder." -ForegroundColor Red
                    Start-Sleep 1
                }
            }

            "0" {
                return $result
            }

            default {
                Write-Host ""
                Write-Host "Invalid option." -ForegroundColor Red
                Start-Sleep 1
            }
        }
    }
}

function Write-CleanupLog {
    param(
        [string]$LogFolder,
        [string[]]$TargetPaths,
        [string]$ModeName,
        [int]$FoundItems,
        [int]$Cleaned,
        [int]$Skipped,
        [int64]$BeforeBytes,
        [int64]$AfterBytes,
        [int64]$CleanedBytes,
        [int64]$SkippedBytes,
        [datetime]$StartedAt,
        [datetime]$FinishedAt,
        [string[]]$CleanedItems,
        [string[]]$SkippedItems
    )

    try {
        $fileName = "ClearTrash_{0}.log" -f $StartedAt.ToString("yyyy-MM-dd_HH-mm-ss")
        $logPath = Join-Path $LogFolder $fileName
        $duration = $FinishedAt - $StartedAt
        $realFreed = $BeforeBytes - $AfterBytes

        if ($realFreed -lt 0) {
            $realFreed = 0
        }

        $lines = @()
        $lines += "ClearTrash Cleanup Log"
        $lines += "----------------------"
        $lines += "Started:            $($StartedAt.ToString('yyyy-MM-dd HH:mm:ss'))"
        $lines += "Finished:           $($FinishedAt.ToString('yyyy-MM-dd HH:mm:ss'))"
        $lines += ("Duration:           {0:N2}s" -f $duration.TotalSeconds)
        $lines += "Mode:               $ModeName"
        $lines += "Found items:        $FoundItems"
        $lines += "Cleaned items:      $Cleaned"
        $lines += "Skipped items:      $Skipped"
        $lines += "Before:             $(Format-Size $BeforeBytes)"
        $lines += "After:              $(Format-Size $AfterBytes)"
        $lines += ""
        $lines += "Real freed:         $(Format-Size $realFreed)"
        $lines += "Cleaned size:       $(Format-Size $CleanedBytes)"
        $lines += "Skipped size:       $(Format-Size $SkippedBytes)"
        $lines += ""
        $lines += "Target folders:"

        foreach ($path in $TargetPaths) {
            $lines += " - $path"
        }

        $lines += ""
        $lines += "Cleaned items:"

        if ($CleanedItems -and $CleanedItems.Count -gt 0) {
            foreach ($item in $CleanedItems) {
                $lines += " + $item"
            }
        }
        else {
            $lines += " + None"
        }

        $lines += ""
        $lines += "Skipped items:"

        if ($SkippedItems -and $SkippedItems.Count -gt 0) {
            foreach ($item in $SkippedItems) {
                $lines += " - $item"
            }
        }
        else {
            $lines += " - None"
        }

        Set-Content -LiteralPath $logPath -Value $lines -Encoding UTF8
        return $logPath
    }
    catch {
        return $null
    }
}

function Write-PreviewLog {
    param(
        [string]$LogFolder,
        [object[]]$TargetSummaries,
        [int]$FoundItems,
        [string]$PotentialFreedText,
        [datetime]$StartedAt,
        [datetime]$FinishedAt,
        [string[]]$SampleItems,
        [string[]]$AllItems,
        [bool]$IncludeAllItems
    )

    try {
        $fileName = "ClearTrash_Preview_{0}.log" -f $StartedAt.ToString("yyyy-MM-dd_HH-mm-ss")
        $logPath = Join-Path $LogFolder $fileName

        $lines = @()
        $lines += "ClearTrash Preview Log"
        $lines += "----------------------"
        $lines += "Started:  $($StartedAt.ToString('yyyy-MM-dd HH:mm:ss'))"
        $lines += "Finished: $($FinishedAt.ToString('yyyy-MM-dd HH:mm:ss'))"
        $lines += "Items:    $FoundItems"
        $lines += "Space:    $PotentialFreedText"
        $lines += ""
        $lines += "Target summary:"

        if ($TargetSummaries -and $TargetSummaries.Count -gt 0) {
            foreach ($summary in $TargetSummaries) {
                $lines += (" - {0}: {1} item(s), {2}" -f $summary.Name, $summary.ItemCount, $summary.SizeText)
                $lines += ("   Path: {0}" -f $summary.Path)
            }
        }
        else {
            $lines += " - None"
        }

        $lines += ""
        $lines += "Sample items:"

        if ($SampleItems -and $SampleItems.Count -gt 0) {
            foreach ($item in $SampleItems) {
                $lines += " - $item"
            }
        }
        else {
            $lines += " - None"
        }

        if ($IncludeAllItems) {
            $lines += ""
            $lines += "All items:"

            if ($AllItems -and $AllItems.Count -gt 0) {
                foreach ($item in $AllItems) {
                    $lines += " - $item"
                }
            }
            else {
                $lines += " - None"
            }
        }

        Set-Content -LiteralPath $logPath -Value $lines -Encoding UTF8
        return $logPath
    }
    catch {
        return $null
    }
}

function Pause-Menu {
    Write-Host ""
    Write-Host "Cleanup paused." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1 - Resume"
    Write-Host "2 - Stop and return to the main menu"
    Write-Host ""

    do {
        $choice = Read-Host "Choice"
    } until ($choice -in @("1", "2"))

    return $choice
}

function After-CleanupMenu {
    Write-Host ""
    Write-Host "1 - Run again"
    Write-Host "2 - Return to the main menu"
    Write-Host "3 - Exit"
    Write-Host ""

    do {
        $choice = Read-Host "Choice"
    } until ($choice -in @("1", "2", "3"))

    return $choice
}

Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class SilentRecycle {

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct SHFILEOPSTRUCT {
        public IntPtr hwnd;
        public uint wFunc;
        public string pFrom;
        public string pTo;
        public ushort fFlags;
        public bool fAnyOperationsAborted;
        public IntPtr hNameMappings;
        public string lpszProgressTitle;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHFileOperation(ref SHFILEOPSTRUCT lpFileOp);

    private const uint FO_DELETE = 3;
    private const ushort FOF_SILENT = 0x0004;
    private const ushort FOF_NOCONFIRMATION = 0x0010;
    private const ushort FOF_ALLOWUNDO = 0x0040;
    private const ushort FOF_NOERRORUI = 0x0400;

    public static int Send(string path)
    {
        SHFILEOPSTRUCT fileOp = new SHFILEOPSTRUCT();
        fileOp.wFunc = FO_DELETE;
        fileOp.pFrom = path + '\0' + '\0';
        fileOp.fFlags = FOF_SILENT | FOF_NOCONFIRMATION | FOF_ALLOWUNDO | FOF_NOERRORUI;

        return SHFileOperation(ref fileOp);
    }
}
"@

function Remove-ToBin($item) {
    $result = [SilentRecycle]::Send($item.FullName)

    if ($result -ne 0) {
        throw "Recycle operation failed"
    }
}

function Remove-Permanent($item) {
    Remove-Item -LiteralPath $item.FullName -Force -Recurse -ErrorAction Stop
}

function Empty-Recycle {
    try {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue | Out-Null
    }
    catch {
    }
}

function Test-DirectDeleteFallbackPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $false
    }

    $fallbackPrefixes = @(
        "$env:WINDIR\Temp",
        "$env:WINDIR\Prefetch",
        "$env:LOCALAPPDATA\Microsoft\Windows\Explorer",
        "$env:ProgramData\Microsoft\Windows Defender\Scans\History",
        "$env:WINDIR\SoftwareDistribution\Download",
        "$env:WINDIR\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache"
    )

    foreach ($prefix in $fallbackPrefixes) {
        if ([string]::IsNullOrWhiteSpace($prefix)) {
            continue
        }

        if ($Path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Remove-SelectedItem($item) {
    switch ($cleanMode) {
        1 {
            try {
                Remove-ToBin $item
            }
            catch {
                if (-not (Test-DirectDeleteFallbackPath -Path $item.FullName)) {
                    throw
                }

                try {
                    Remove-Permanent $item
                }
                catch {
                    $recycleReason = $_.Exception.Message
                    if ([string]::IsNullOrWhiteSpace($recycleReason)) {
                        $recycleReason = "Recycle operation failed"
                    }

                    $permanentReason = $_.Exception.Message
                    if ([string]::IsNullOrWhiteSpace($permanentReason)) {
                        $permanentReason = "Direct delete failed"
                    }

                    throw ("Recycle failed; direct delete fallback also failed ({0})" -f $permanentReason)
                }
            }
        }
        2 { Remove-Permanent $item }
        3 {
            try {
                Remove-ToBin $item
            }
            catch {
                if (-not (Test-DirectDeleteFallbackPath -Path $item.FullName)) {
                    throw
                }

                try {
                    Remove-Permanent $item
                }
                catch {
                    $permanentReason = $_.Exception.Message
                    if ([string]::IsNullOrWhiteSpace($permanentReason)) {
                        $permanentReason = "Direct delete failed"
                    }

                    throw ("Recycle failed; direct delete fallback also failed ({0})" -f $permanentReason)
                }
            }
        }
    }
}

function Resolve-SelectionTargets {
    param([string[]]$Selection)

    $selectedTargets = @()

    foreach ($key in $Selection) {
        $target = Get-Target $key
        if ($target) {
            $selectedTargets += $target
        }
    }

    return $selectedTargets
}

function Get-PreviewData {
    param([object[]]$SelectedTargets)

    $allItems = New-Object System.Collections.Generic.List[string]
    $summaries = New-Object System.Collections.Generic.List[object]
    $totalBytes = 0L
    $totalCount = 0

    foreach ($target in $SelectedTargets) {
        $targetCount = 0
        $targetBytes = 0L

        if (Test-Path -LiteralPath $target.Path) {
            try {
                foreach ($item in (Get-ChildItem -LiteralPath $target.Path -Force -ErrorAction SilentlyContinue)) {
                    $allItems.Add($item.FullName)
                    $itemSize = Get-ItemSize $item
                    $targetBytes += $itemSize
                    $targetCount++
                    $totalBytes += $itemSize
                    $totalCount++
                }
            }
            catch {
            }
        }

        $summaries.Add([pscustomobject]@{
            Name      = $target.Name
            Path      = $target.Path
            ItemCount = $targetCount
            SizeBytes = $targetBytes
            SizeText  = (Format-Size $targetBytes)
        })
    }

    return [pscustomobject]@{
        Items       = [object[]]$allItems.ToArray()
        Summaries   = [object[]]$summaries.ToArray()
        TotalBytes  = $totalBytes
        TotalCount  = $totalCount
    }
}

function Get-PreviewItems {
    param([object[]]$SelectedTargets)

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($target in $SelectedTargets) {
        if (!(Test-Path -LiteralPath $target.Path)) {
            continue
        }

        try {
            foreach ($item in (Get-ChildItem -LiteralPath $target.Path -Force -ErrorAction SilentlyContinue)) {
                $items.Add($item)
            }
        }
        catch {
        }
    }

    return [object[]]$items.ToArray()
}

function Confirm-Cleanup {
    param(
        [object[]]$SelectedTargets,
        [int]$FoundItems,
        [int64]$PotentialBytes
    )

    if (-not $script:requireConfirmation) {
        return $true
    }

    Write-Host ""
    Write-Host "Review before cleanup" -ForegroundColor Yellow
    Write-Host "─────────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("Targets:         {0}" -f $SelectedTargets.Count) -ForegroundColor White
    Write-Host ("Found items:     {0}" -f $FoundItems) -ForegroundColor White
    Write-Host ("Potential space: {0}" -f (Format-Size $PotentialBytes)) -ForegroundColor White
    Write-Host ("Mode:            {0}" -f (Get-ModeText)) -ForegroundColor White
    Write-Host ""

    $answer = Read-Host "Continue with cleanup? (Y/N)"
    return ($answer -match '^(?i)y(es)?$')
}

function Try-RemoveSelectedItem($item) {
    $attempt = 0

    while ($true) {
        try {
            Remove-SelectedItem $item
            return $true
        }
        catch {
            if ($attempt -ge $script:retryCount) {
                throw
            }

            $attempt++

            if ($script:retryDelayMs -gt 0) {
                Start-Sleep -Milliseconds $script:retryDelayMs
            }
        }
    }
}

function Get-ServiceCleanupPlan {
    param([object[]]$SelectedTargets)

    $names = New-Object System.Collections.Generic.List[string]

    foreach ($target in $SelectedTargets) {
        if ($null -eq $target -or [string]::IsNullOrWhiteSpace([string]$target.Path)) {
            continue
        }

        $path = [string]$target.Path

        if ($path -like 'C:\Windows\SoftwareDistribution\Download*') {
            foreach ($svc in @('wuauserv', 'BITS')) {
                if (-not $names.Contains($svc)) {
                    $names.Add($svc)
                }
            }
        }

        if ($path -like 'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache*') {
            if (-not $names.Contains('DoSvc')) {
                $names.Add('DoSvc')
            }
        }
    }

    return [string[]]$names.ToArray()
}

function Stop-CleanupServices {
    param([string[]]$ServiceNames)

    $stopped = New-Object System.Collections.Generic.List[string]

    if ($null -eq $ServiceNames -or $ServiceNames.Count -eq 0) {
        return [string[]]$stopped.ToArray()
    }

    foreach ($serviceName in $ServiceNames) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop

            if ($service.Status -eq 'Running') {
                Write-Host ('Stopping service: {0}' -f $serviceName) -ForegroundColor DarkGray
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                $stopped.Add($serviceName)
            }
        }
        catch {
        }
    }

    if ($stopped.Count -gt 0) {
        Start-Sleep -Milliseconds 500
    }

    return [string[]]$stopped.ToArray()
}

function Start-CleanupServices {
    param([string[]]$ServiceNames)

    if ($null -eq $ServiceNames -or $ServiceNames.Count -eq 0) {
        return
    }

    foreach ($serviceName in $ServiceNames) {
        try {
            Write-Host ('Starting service: {0}' -f $serviceName) -ForegroundColor DarkGray
            Start-Service -Name $serviceName -ErrorAction Stop
        }
        catch {
        }
    }
}

function Show-CleanupSummary {
    param(
        $StartedAt,
        $FinishedAt,
        [string]$ModeName,
        [int]$FoundItems,
        [int]$CleanedItems,
        [int]$SkippedItems,
        [int64]$BeforeBytes,
        [int64]$AfterBytes,
        [int64]$CleanedBytes,
        [int64]$SkippedBytes
    )

    $safeStart = Get-DateTimeValue $StartedAt
    $safeEnd = Get-DateTimeValue $FinishedAt
    $duration = $safeEnd - $safeStart
    $realFreed = $BeforeBytes - $AfterBytes

    if ($realFreed -lt 0) {
        $realFreed = 0
    }

    Write-Host ("Started:            {0}" -f $safeStart.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
    Write-Host ("Finished:           {0}" -f $safeEnd.ToString("yyyy-MM-dd HH:mm:ss")) -ForegroundColor White
    Write-Host ("Duration:           {0:N2}s" -f $duration.TotalSeconds) -ForegroundColor Cyan
    Write-Host ("Mode:               {0}" -f $ModeName) -ForegroundColor Cyan
    Write-Host ("Found items:        {0}" -f $FoundItems) -ForegroundColor White
    Write-Host ("Cleaned items:      {0}" -f $CleanedItems) -ForegroundColor Green
    Write-Host ("Skipped items:      {0}" -f $SkippedItems) -ForegroundColor Yellow
    Write-Host ("Before:             {0}" -f (Format-Size $BeforeBytes)) -ForegroundColor White
    Write-Host ("After:              {0}" -f (Format-Size $AfterBytes)) -ForegroundColor White
    Write-Host ""
    Write-Host ("Real freed:         {0}" -f (Format-Size $realFreed)) -ForegroundColor Green
    Write-Host ("Cleaned size:       {0}" -f (Format-Size $CleanedBytes)) -ForegroundColor Green
    Write-Host ("Skipped size:       {0}" -f (Format-Size $SkippedBytes)) -ForegroundColor Yellow
}

function Write-JsonLog {
    param(
        [string]$LogFolder,
        [datetime]$StartedAt,
        [string]$FilePrefix,
        $Payload
    )

    if (-not $script:writeJsonLog) {
        return $null
    }

    try {
        $fileName = "{0}_{1}.json" -f $FilePrefix, $StartedAt.ToString("yyyy-MM-dd_HH-mm-ss")
        $jsonPath = Join-Path $LogFolder $fileName
        $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        return $jsonPath
    }
    catch {
        return $null
    }
}

function Start-Preview($selection) {
    if (!$selection -or $selection.Count -eq 0) {
        Show-Header
        Write-Host "No valid folder was selected." -ForegroundColor Red
        Start-Sleep 1
        return "menu"
    }

    $selectedTargets = Resolve-SelectionTargets -Selection $selection

    if ($selectedTargets.Count -eq 0) {
        Show-Header
        Write-Host "No valid folder was selected." -ForegroundColor Red
        Start-Sleep 1
        return "menu"
    }

    $logSettings = Ask-LogSettings
    $startTime = Get-Date

    Show-Header
    Write-Host "Preview mode" -ForegroundColor Cyan
    Write-Host "────────────" -ForegroundColor DarkGray
    Write-Host ""

    $previewData = Get-PreviewData -SelectedTargets $selectedTargets
    $items = @($previewData.Items)
    $total = [int]$previewData.TotalCount
    $potentialFreedBytes = [int64]$previewData.TotalBytes
    $targetSummaries = @($previewData.Summaries)
    $sampleItems = New-Object System.Collections.Generic.List[string]

    for ($i = 0; $i -lt $items.Count; $i++) {
        $current = $i + 1
        Show-ProgressBar $current $total

        if ($sampleItems.Count -lt $script:previewSampleLimit) {
            $sampleItems.Add([string]$items[$i])
        }
    }

    if ($total -gt 0) {
        Write-Host ""
    }

    $endTime = Get-Date
    $duration = $endTime - $startTime
    $potentialFreedText = Format-Size $potentialFreedBytes
    $logPath = $null
    $jsonLogPath = $null

    if ($logSettings.Enabled) {
        $logPath = Write-PreviewLog `
            -LogFolder $logSettings.Folder `
            -TargetSummaries $targetSummaries `
            -FoundItems $total `
            -PotentialFreedText $potentialFreedText `
            -StartedAt $startTime `
            -FinishedAt $endTime `
            -SampleItems ([string[]]$sampleItems.ToArray()) `
            -AllItems ([string[]]$items) `
            -IncludeAllItems $script:previewFullLog

        $jsonLogPath = Write-JsonLog `
            -LogFolder $logSettings.Folder `
            -StartedAt $startTime `
            -FilePrefix "ClearTrash_Preview" `
            -Payload ([ordered]@{
                startedAt      = $startTime.ToString("yyyy-MM-dd HH:mm:ss")
                finishedAt     = $endTime.ToString("yyyy-MM-dd HH:mm:ss")
                foundItems     = $total
                potentialBytes = $potentialFreedBytes
                targets        = @($targetSummaries)
                sampleItems    = [string[]]$sampleItems.ToArray()
            })
    }

    Write-Host ""
    Write-Host "Preview complete" -ForegroundColor Green
    Write-Host "────────────────" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host ("Selected targets: {0}" -f $selectedTargets.Count) -ForegroundColor Cyan
    Write-Host ("Matched items:    {0}" -f $total) -ForegroundColor Green
    Write-Host ("Potential space:  {0}" -f $potentialFreedText) -ForegroundColor Green
    Write-Host ("Scan time:        {0:N2}s" -f $duration.TotalSeconds) -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Breakdown by target:" -ForegroundColor Yellow
    foreach ($summary in $targetSummaries) {
        if ($summary.ItemCount -gt 0 -or $summary.SizeBytes -gt 0) {
            Write-Host (" - {0}: {1} item(s), {2}" -f $summary.Name, $summary.ItemCount, $summary.SizeText) -ForegroundColor White
        }
    }
    Write-Host ""

    if ($sampleItems.Count -gt 0) {
        Write-Host ("Showing up to {0} item(s):" -f $script:previewSampleLimit) -ForegroundColor Yellow
        foreach ($sample in $sampleItems) {
            Write-Host (" - {0}" -f $sample) -ForegroundColor White
        }

        if ($total -gt $sampleItems.Count) {
            Write-Host (" ... and {0} more item(s)" -f ($total - $sampleItems.Count)) -ForegroundColor DarkGray
        }
    }
    else {
        Write-Host "Nothing was found to clean." -ForegroundColor Yellow
    }

    if ($logSettings.Enabled) {
        Write-Host ""
        if ($logPath) {
            Write-Host ("Log saved:   {0}" -f $logPath) -ForegroundColor Cyan
            if ($script:previewFullLog) {
                Write-Host "Full preview item list was written to the log." -ForegroundColor DarkGray
            }
        }
        else {
            Write-Host "Log could not be saved." -ForegroundColor Yellow
        }

        if ($jsonLogPath) {
            Write-Host ("JSON log saved: {0}" -f $jsonLogPath) -ForegroundColor Cyan
        }
    }

    $next = After-CleanupMenu
    switch ($next) {
        "1" { return "rerun" }
        "2" { return "menu" }
        "3" { return "exit" }
    }
}

function Start-Cleanup($selection) {
    if (!$selection -or $selection.Count -eq 0) {
        Show-Header
        Write-Host "No valid folder was selected." -ForegroundColor Red
        Start-Sleep 1
        return "menu"
    }

    $selectedTargets = Resolve-SelectionTargets -Selection $selection

    if ($selectedTargets.Count -eq 0) {
        Show-Header
        Write-Host "No valid folder was selected." -ForegroundColor Red
        Start-Sleep 1
        return "menu"
    }

    $previewData = Get-PreviewData -SelectedTargets $selectedTargets
    $foundItems = [int]$previewData.TotalCount
    $beforeBytes = [int64]$previewData.TotalBytes

    Show-Header

    if (-not (Confirm-Cleanup -SelectedTargets $selectedTargets -FoundItems $foundItems -PotentialBytes $beforeBytes)) {
        Write-Host ""
        Write-Host "Cleanup canceled." -ForegroundColor Yellow
        Start-Sleep 1
        return "menu"
    }

    $logSettings = Ask-LogSettings
    $startTime = Get-Date

    Show-Header
    Write-Host "Starting cleanup" -ForegroundColor Cyan
    Write-Host "────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "Targets:" -ForegroundColor Yellow
    foreach ($target in $selectedTargets) {
        Write-Host (" - {0}" -f $target.Name)
    }

    Write-Host ""
    Write-Host "Press SPACE to pause" -ForegroundColor DarkGray
    Write-Host ""

    $servicePlan = Get-ServiceCleanupPlan -SelectedTargets $selectedTargets
    $stoppedServices = @()

    if ($servicePlan.Count -gt 0) {
        $stoppedServices = Stop-CleanupServices -ServiceNames $servicePlan
    }

    $items = Get-PreviewItems -SelectedTargets $selectedTargets
    $total = $items.Count
    $cleaned = 0
    $skipped = 0
    $cleanedBytes = 0L
    $skippedBytes = 0L
    $cleanedItems = New-Object System.Collections.Generic.List[string]
    $skippedItems = New-Object System.Collections.Generic.List[string]

    if ($total -eq 0) {
        if ($stoppedServices.Count -gt 0) {
            Start-CleanupServices -ServiceNames $stoppedServices
            Write-Host ""
        }

        Write-Host "Nothing was found to clean." -ForegroundColor Yellow
        $next = After-CleanupMenu
        switch ($next) {
            "1" { return "rerun" }
            "2" { return "menu" }
            "3" { return "exit" }
        }
    }

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $current = $i + 1
        $itemSize = Get-ItemSize $item

        Show-ProgressBar $current $total

        try {
            if ([Console]::KeyAvailable) {
                $key = [Console]::ReadKey($true)
                if ($key.Key -eq [ConsoleKey]::Spacebar) {
                    Write-Host ""

                    $pauseChoice = Pause-Menu
                    if ($pauseChoice -eq "2") {
                        return "menu"
                    }

                    Show-Header
                    Write-Host "Resuming cleanup..." -ForegroundColor Cyan
                    Write-Host ""
                }
            }
        }
        catch {
        }

        try {
            Try-RemoveSelectedItem $item | Out-Null
            $cleaned++
            $cleanedBytes += $itemSize
            Add-DetailEntry -List $cleanedItems -Value $item.FullName
        }
        catch {
            $skipped++
            $skippedBytes += $itemSize

            $reason = $_.Exception.Message
            if ([string]::IsNullOrWhiteSpace($reason) -and $null -ne $_.Exception.InnerException) {
                $reason = $_.Exception.InnerException.Message
            }
            if ([string]::IsNullOrWhiteSpace($reason)) {
                $reason = "Unknown error"
            }

            Add-DetailEntry -List $skippedItems -Value ("{0} | {1}" -f $item.FullName, $reason)
        }
    }

    Write-Host ""

    if ($stoppedServices.Count -gt 0) {
        Write-Host ""
        Start-CleanupServices -ServiceNames $stoppedServices
    }

    if ($cleanMode -eq 3) {
        Empty-Recycle
    }

    $endTime = Get-Date
    $afterBytes = 0

    foreach ($target in $selectedTargets) {
        $afterBytes += Get-FolderSize $target.Path
    }

    $logPath = $null
    $jsonLogPath = $null

    if ($logSettings.Enabled) {
        $logPath = Write-CleanupLog `
            -LogFolder $logSettings.Folder `
            -TargetPaths ($selectedTargets | ForEach-Object { $_.Path }) `
            -ModeName (Get-ModeText) `
            -FoundItems $foundItems `
            -Cleaned $cleaned `
            -Skipped $skipped `
            -BeforeBytes $beforeBytes `
            -AfterBytes $afterBytes `
            -CleanedBytes $cleanedBytes `
            -SkippedBytes $skippedBytes `
            -StartedAt $startTime `
            -FinishedAt $endTime `
            -CleanedItems ([string[]]$cleanedItems.ToArray()) `
            -SkippedItems ([string[]]$skippedItems.ToArray())

        $jsonLogPath = Write-JsonLog `
            -LogFolder $logSettings.Folder `
            -StartedAt $startTime `
            -FilePrefix "ClearTrash_Cleanup" `
            -Payload ([ordered]@{
                startedAt    = $startTime.ToString("yyyy-MM-dd HH:mm:ss")
                finishedAt   = $endTime.ToString("yyyy-MM-dd HH:mm:ss")
                mode         = Get-ModeText
                foundItems   = $foundItems
                cleanedItems = $cleaned
                skippedItems = $skipped
                beforeBytes  = $beforeBytes
                afterBytes   = $afterBytes
                cleanedBytes = $cleanedBytes
                skippedBytes = $skippedBytes
                targets      = @($selectedTargets | ForEach-Object { $_.Path })
            })
    }

    Write-Host ""
    Write-Host "Cleanup complete" -ForegroundColor Green
    Write-Host "────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Show-CleanupSummary `
        -StartedAt $startTime `
        -FinishedAt $endTime `
        -ModeName (Get-ModeText) `
        -FoundItems $foundItems `
        -CleanedItems $cleaned `
        -SkippedItems $skipped `
        -BeforeBytes $beforeBytes `
        -AfterBytes $afterBytes `
        -CleanedBytes $cleanedBytes `
        -SkippedBytes $skippedBytes

    Write-Host ""

    switch ($cleanMode) {
        1 { Write-Host "The cleaned files were sent to the Recycle Bin." -ForegroundColor Green }
        2 { Write-Host "The cleaned files were permanently deleted." -ForegroundColor Green }
        3 { Write-Host "The cleaned files were sent to the Recycle Bin and the Recycle Bin was emptied." -ForegroundColor Green }
    }

    if ($logSettings.Enabled) {
        Write-Host ""

        if ($logPath) {
            Write-Host ("Log saved:        {0}" -f $logPath) -ForegroundColor Cyan
        }
        else {
            Write-Host "Log could not be saved." -ForegroundColor Yellow
        }

        if ($jsonLogPath) {
            Write-Host ("JSON log saved:   {0}" -f $jsonLogPath) -ForegroundColor Cyan
        }
    }

    $next = After-CleanupMenu
    switch ($next) {
        "1" { return "rerun" }
        "2" { return "menu" }
        "3" { return "exit" }
    }
}

function Open-ConfigFolder {
    if (!(Test-Path -LiteralPath $configFilePath)) {
        Save-Config (Get-DefaultConfig) | Out-Null
    }

    try {
        Start-Process explorer.exe $scriptRoot | Out-Null
    }
    catch {
        Show-Header
        Write-Host "Unable to open the config folder." -ForegroundColor Red
        Start-Sleep 1
    }
}

Refresh-Settings

if (!(Is-Admin)) {
    Clear-Host
    Write-Host "This script must be run as Administrator." -ForegroundColor Red
    Write-Host ""
    Pause
    exit
}

while ($true) {
    Show-MainMenu
    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" {
            do {
                $selection = Select-Folders
                $result = Start-Cleanup $selection
            } while ($result -eq "rerun")

            if ($result -eq "exit") {
                exit
            }
        }

        "2" {
            Change-Mode
        }

        "3" {
            do {
                $selection = Select-Folders
                $result = Start-Preview $selection
            } while ($result -eq "rerun")

            if ($result -eq "exit") {
                exit
            }
        }

        "4" {
            Open-ConfigFolder
        }

        "5" {
            try {
                Start-Process $githubUrl | Out-Null
            }
            catch {
                Write-Host ""
                Write-Host "Unable to open the GitHub page." -ForegroundColor Red
                Start-Sleep 1
            }
        }

        "6" {
            exit
        }

        default {
            Write-Host ""
            Write-Host "Invalid option." -ForegroundColor Red
            Start-Sleep -Milliseconds 900
        }
    }
}
