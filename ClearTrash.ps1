try {
    $rawUI = $Host.UI.RawUI

    $width = 68
    $height = 20
    $bufferHeight = 500

    if ($rawUI.BufferSize.Width -lt $width) {
        $rawUI.BufferSize = New-Object Management.Automation.Host.Size($width, $rawUI.BufferSize.Height)
    }

    $rawUI.WindowSize = New-Object Management.Automation.Host.Size($width, $height)
    $rawUI.BufferSize = New-Object Management.Automation.Host.Size($width, $bufferHeight)
}
catch {
}

Add-Type -AssemblyName Microsoft.VisualBasic

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

$defaultLogFolder = Join-Path $scriptRoot "logs"

$targets = @(
    @{ Key = "1"; Name = "User TEMP"; Path = $env:TEMP },
    @{ Key = "2"; Name = "Windows TEMP"; Path = "C:\Windows\Temp" },
    @{ Key = "3"; Name = "Prefetch"; Path = "C:\Windows\Prefetch" }
)

function Is-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($id)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Show-Header {
    Clear-Host

    Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              CLEARTRASH              ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
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

function Get-Target($key) {
    return $targets | Where-Object { $_.Key -eq $key } | Select-Object -First 1
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
    Write-Host "[3] Creator GitHub" -ForegroundColor White
    Write-Host "[4] Exit" -ForegroundColor White
    Write-Host ""
}

function Show-ProgressBar($current, $total) {
    if ($total -le 0) {
        return
    }

    $percent = [math]::Floor(($current / $total) * 100)
    $width = 24
    $filled = [math]::Floor(($percent / 100) * $width)

    $bar = ("█" * $filled).PadRight($width, "░")
    $line = "[{0}] {1,3}%  {2}/{3}" -f $bar, $percent, $current, $total

    Write-Host -NoNewline "`r$line"
}

function Select-Folders {
    Show-Header

    Write-Host "Choose what to clean" -ForegroundColor Yellow
    Write-Host "────────────────────" -ForegroundColor DarkGray
    Write-Host ""

    foreach ($target in $targets) {
        Write-Host ("[{0}] {1}" -f $target.Key, $target.Name)
    }

    Write-Host ""
    Write-Host "Type: 1   or   1,2   or   all" -ForegroundColor DarkGray
    Write-Host ""

    $inputValue = Read-Host "Selection"

    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return @()
    }

    if ($inputValue.Trim().ToLower() -eq "all") {
        return $targets.Key
    }

    $selected = @()

    foreach ($part in ($inputValue -split ",")) {
        $key = $part.Trim()
        if ($targets.Key -contains $key -and $selected -notcontains $key) {
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
    $saveLog = Read-Host "Do you want to save a cleanup log? (Y/N)"

    if ($saveLog -notmatch '^(?i)y(es)?$') {
        return $result
    }

    while ($true) {
        Show-Header
        Write-Host "Log options" -ForegroundColor Yellow
        Write-Host "───────────" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "[1] Default"
        Write-Host ("    Save in: {0}" -f $defaultLogFolder) -ForegroundColor DarkGray
        Write-Host "[2] Custom path"
        Write-Host "    Example: C:\Users\YourName\Documents\ClearTrashLogs" -ForegroundColor DarkGray
        Write-Host "[0] Cancel log"
        Write-Host ""

        $choice = Read-Host "Select option"

        switch ($choice) {
            "1" {
                try {
                    if (!(Test-Path -LiteralPath $defaultLogFolder)) {
                        New-Item -ItemType Directory -Path $defaultLogFolder -Force | Out-Null
                    }

                    if (Test-Path -LiteralPath $defaultLogFolder -PathType Container) {
                        $result.Enabled = $true
                        $result.Folder = $defaultLogFolder
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

                    if (!(Test-Path -LiteralPath $folder)) {
                        $create = Read-Host "Folder does not exist. Create it? (Y/N)"
                        if ($create -match '^(?i)y(es)?$') {
                            try {
                                New-Item -ItemType Directory -Path $folder -Force | Out-Null
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

                    if (Test-Path -LiteralPath $folder -PathType Container) {
                        $result.Enabled = $true
                        $result.Folder = $folder
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
        [int]$Cleaned,
        [int]$Skipped,
        [string]$SpaceCleaned,
        [datetime]$StartedAt,
        [datetime]$FinishedAt,
        [string[]]$CleanedItems,
        [string[]]$SkippedItems
    )

    try {
        $fileName = "ClearTrash_{0}.log" -f $StartedAt.ToString("yyyy-MM-dd_HH-mm-ss")
        $logPath = Join-Path $LogFolder $fileName

        $lines = @()
        $lines += "ClearTrash Cleanup Log"
        $lines += "----------------------"
        $lines += "Started:  $($StartedAt.ToString('yyyy-MM-dd HH:mm:ss'))"
        $lines += "Finished: $($FinishedAt.ToString('yyyy-MM-dd HH:mm:ss'))"
        $lines += "Mode:     $ModeName"
        $lines += "Cleaned:  $Cleaned"
        $lines += "Skipped:  $Skipped"
        $lines += "Space:    $SpaceCleaned"
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
    Write-Host "1 - Run another cleanup"
    Write-Host "2 - Return to the main menu"
    Write-Host "3 - Exit"
    Write-Host ""

    do {
        $choice = Read-Host "Choice"
    } until ($choice -in @("1", "2", "3"))

    return $choice
}

function Remove-ToBin($item) {
    if ($item.PSIsContainer) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $item.FullName,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
    else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $item.FullName,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
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

function Remove-SelectedItem($item) {
    switch ($cleanMode) {
        1 { Remove-ToBin $item }
        2 { Remove-Permanent $item }
        3 { Remove-ToBin $item }
    }
}

function Start-Cleanup($selection) {
    if (!$selection -or $selection.Count -eq 0) {
        Show-Header
        Write-Host "No valid folder was selected." -ForegroundColor Red
        Start-Sleep 1
        return "menu"
    }

    $selectedTargets = @()

    foreach ($key in $selection) {
        $target = Get-Target $key
        if ($target) {
            $selectedTargets += $target
        }
    }

    if ($selectedTargets.Count -eq 0) {
        Show-Header
        Write-Host "No valid folder was selected." -ForegroundColor Red
        Start-Sleep 1
        return "menu"
    }

    $logSettings = Ask-LogSettings
    $startTime = Get-Date
    $beforeBytes = 0

    foreach ($target in $selectedTargets) {
        $beforeBytes += Get-FolderSize $target.Path
    }

    Show-Header
    Write-Host "Starting cleanup" -ForegroundColor Cyan
    Write-Host "────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host "Targets:" -ForegroundColor Yellow
    foreach ($target in $selectedTargets) {
        Write-Host (" • {0}" -f $target.Name)
    }

    Write-Host ""
    Write-Host "Press SPACE to pause" -ForegroundColor DarkGray
    Write-Host ""

    $items = @()

    foreach ($target in $selectedTargets) {
        if (Test-Path -LiteralPath $target.Path) {
            $items += Get-ChildItem -LiteralPath $target.Path -Force -ErrorAction SilentlyContinue
        }
    }

    $total = $items.Count
    $cleaned = 0
    $skipped = 0
    $cleanedBytes = 0L
    $cleanedItems = New-Object System.Collections.Generic.List[string]
    $skippedItems = New-Object System.Collections.Generic.List[string]

    if ($total -eq 0) {
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
            $itemSize = Get-ItemSize $item
            Remove-SelectedItem $item

            $cleaned++
            $cleanedBytes += $itemSize
            $cleanedItems.Add($item.FullName)
        }
        catch {
            $skipped++
            $skippedItems.Add($item.FullName)
        }
    }

    Write-Host ""

    if ($cleanMode -eq 3) {
        Empty-Recycle
    }

    $endTime = Get-Date
    $duration = $endTime - $startTime
    $afterBytes = 0

    foreach ($target in $selectedTargets) {
        $afterBytes += Get-FolderSize $target.Path
    }

    $freedBytes = $cleanedBytes
    $beforeText = Format-Size $beforeBytes
    $afterText = Format-Size $afterBytes
    $freedText = Format-Size $freedBytes
    $logPath = $null

    if ($logSettings.Enabled) {
        $logPath = Write-CleanupLog `
            -LogFolder $logSettings.Folder `
            -TargetPaths ($selectedTargets | ForEach-Object { $_.Path }) `
            -ModeName (Get-ModeText) `
            -Cleaned $cleaned `
            -Skipped $skipped `
            -SpaceCleaned $freedText `
            -StartedAt $startTime `
            -FinishedAt $endTime `
            -CleanedItems $cleanedItems `
            -SkippedItems $skippedItems
    }

    Write-Host ""
    Write-Host "Cleanup complete" -ForegroundColor Green
    Write-Host "────────────────" -ForegroundColor DarkGray
    Write-Host ""

    Write-Host ("Mode:        {0}" -f (Get-ModeText)) -ForegroundColor Cyan
    Write-Host ("Cleaned:     {0}" -f $cleaned) -ForegroundColor Green
    Write-Host ("Skipped:     {0}" -f $skipped) -ForegroundColor Yellow
    Write-Host ("Before:      {0}" -f $beforeText) -ForegroundColor White
    Write-Host ("After:       {0}" -f $afterText) -ForegroundColor White
    Write-Host ("Freed:       {0}" -f $freedText) -ForegroundColor Green
    Write-Host ("Time:        {0:N2}s" -f $duration.TotalSeconds) -ForegroundColor Cyan

    switch ($cleanMode) {
        1 { Write-Host "The cleaned files were sent to the Recycle Bin." -ForegroundColor Green }
        2 { Write-Host "The cleaned files were permanently deleted." -ForegroundColor Green }
        3 { Write-Host "The cleaned files were sent to the Recycle Bin and the Recycle Bin was emptied." -ForegroundColor Green }
    }

    if ($logSettings.Enabled) {
        Write-Host ""

        if ($logPath) {
            Write-Host ("Log saved:   {0}" -f $logPath) -ForegroundColor Cyan
        }
        else {
            Write-Host "Log could not be saved." -ForegroundColor Yellow
        }
    }

    $next = After-CleanupMenu
    switch ($next) {
        "1" { return "rerun" }
        "2" { return "menu" }
        "3" { return "exit" }
    }
}

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
            try {
                Start-Process $githubUrl | Out-Null
            }
            catch {
                Write-Host ""
                Write-Host "Unable to open the GitHub page." -ForegroundColor Red
                Start-Sleep 1
            }
        }

        "4" {
            exit
        }

        default {
            Write-Host ""
            Write-Host "Invalid option." -ForegroundColor Red
            Start-Sleep -Milliseconds 900
        }
    }
}