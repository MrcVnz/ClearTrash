Add-Type -AssemblyName Microsoft.VisualBasic

$githubUrl = "https://github.com/MrcVnz"
$cleanMode = 1

$folderMap = [ordered]@{
    "1" = @{
        Label = "User TEMP"
        Path  = $env:TEMP
    }
    "2" = @{
        Label = "Windows TEMP"
        Path  = "C:\Windows\Temp"
    }
    "3" = @{
        Label = "Prefetch"
        Path  = "C:\Windows\Prefetch"
    }
}

function Show-Top {
    Clear-Host
    Write-Host "Running as Administrator..." -ForegroundColor Cyan
    Write-Host ""
}

function Get-ModeName {
    switch ($cleanMode) {
        1 { "Recycle Bin" }
        2 { "Permanent Delete" }
        3 { "Recycle Bin + Empty Bin" }
        default { "Unknown" }
    }
}

function Format-Size {
    param(
        [Int64]$Bytes
    )

    if ($Bytes -ge 1GB) {
        return ("{0:N2} GB" -f ($Bytes / 1GB))
    }

    if ($Bytes -ge 1MB) {
        return ("{0:N2} MB" -f ($Bytes / 1MB))
    }

    if ($Bytes -ge 1KB) {
        return ("{0:N2} KB" -f ($Bytes / 1KB))
    }

    return ("{0} B" -f $Bytes)
}

function Get-EntrySize {
    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    try {
        if (-not $Entry.PSIsContainer) {
            return [Int64]$Entry.Length
        }

        $size = 0L

        Get-ChildItem -LiteralPath $Entry.FullName -Force -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            $size += [Int64]$_.Length
        }

        return $size
    }
    catch {
        return 0L
    }
}

function Show-MainMenu {
    Show-Top

    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host "           CLEARTRASH              " -ForegroundColor Cyan
    Write-Host "===================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "Current mode: " -NoNewline
    switch ($cleanMode) {
        1 { Write-Host "Recycle Bin" -ForegroundColor Green }
        2 { Write-Host "Permanent Delete" -ForegroundColor Yellow }
        3 { Write-Host "Recycle Bin + Empty Bin" -ForegroundColor Magenta }
        default { Write-Host "Unknown" -ForegroundColor Red }
    }

    Write-Host ""
    Write-Host "1 - Start cleaning"
    Write-Host "2 - Change cleaning mode"
    Write-Host "3 - Creator GitHub"
    Write-Host "4 - Exit"
    Write-Host ""
}

function Pick-Folders {
    Show-Top

    Write-Host "Choose what you want to clean:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1 - User TEMP"
    Write-Host "2 - Windows TEMP"
    Write-Host "3 - Prefetch"
    Write-Host ""
    Write-Host "Examples: 1   or   1,2   or   1,2,3" -ForegroundColor DarkGray
    Write-Host ""

    $raw = Read-Host "Selection"

    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @()
    }

    $picked = @()

    foreach ($part in ($raw -split ",")) {
        $key = $part.Trim()
        if ($folderMap.Contains($key) -and $picked -notcontains $key) {
            $picked += $key
        }
    }

    return $picked
}

function Change-Mode {
    Show-Top

    Write-Host "Cleaning mode:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "1 - Send files to Recycle Bin"
    Write-Host "2 - Permanently delete files"
    Write-Host "3 - Send to Recycle Bin and empty it after cleaning"
    Write-Host ""

    $choice = Read-Host "Select mode"

    switch ($choice) {
        "1" { $script:cleanMode = 1 }
        "2" { $script:cleanMode = 2 }
        "3" { $script:cleanMode = 3 }
        default {
            Write-Host ""
            Write-Host "Invalid option." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}

function Show-Targets {
    param(
        [string[]]$Paths
    )

    Show-Top
    Write-Host "Starting cleanup..." -ForegroundColor Cyan
    Write-Host "Target folders:" -ForegroundColor Cyan

    foreach ($path in $Paths) {
        Write-Host (" - {0}" -f $path)
    }

    Write-Host ""
    Write-Host "Press SPACE to pause the cleanup." -ForegroundColor DarkGray
    Write-Host ""
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

function Ask-LogSettings {
    $result = @{
        Enabled = $false
        Folder  = $null
    }

    Write-Host ""
    $saveLog = Read-Host "Save a cleanup log? (Y/N)"

    if ($saveLog -notmatch '^(?i)y(es)?$') {
        return $result
    }

    while ($true) {
        Write-Host ""
        Write-Host "Type the folder where the log should be saved." -ForegroundColor Yellow
        Write-Host "Example: C:\Logs" -ForegroundColor DarkGray
        Write-Host "Type 0 to cancel log saving." -ForegroundColor DarkGray
        Write-Host ""

        $folder = Read-Host "Log folder"

        if ($folder -eq "0") {
            return $result
        }

        if ([string]::IsNullOrWhiteSpace($folder)) {
            Write-Host "Folder cannot be empty." -ForegroundColor Red
            continue
        }

        if (Test-Path -LiteralPath $folder -PathType Container) {
            $result.Enabled = $true
            $result.Folder = $folder
            return $result
        }

        Write-Host "That folder does not exist." -ForegroundColor Red
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
        [datetime]$FinishedAt
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

        Set-Content -LiteralPath $logPath -Value $lines -Encoding UTF8
        return $logPath
    }
    catch {
        return $null
    }
}

function Send-ToBin {
    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    if ($Entry.PSIsContainer) {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
            $Entry.FullName,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
    else {
        [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
            $Entry.FullName,
            [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
            [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin
        )
    }
}

function Delete-Forever {
    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    Remove-Item -LiteralPath $Entry.FullName -Force -Recurse -ErrorAction Stop
}

function Empty-Bin {
    try {
        Clear-RecycleBin -Force -ErrorAction Stop | Out-Null
    }
    catch {
    }
}

function Remove-OneItem {
    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    switch ($cleanMode) {
        1 { Send-ToBin -Entry $Entry }
        2 { Delete-Forever -Entry $Entry }
        3 { Send-ToBin -Entry $Entry }
    }
}

function Start-Cleaning {
    param(
        [string[]]$Selection
    )

    if (-not $Selection -or $Selection.Count -eq 0) {
        Show-Top
        Write-Host "No valid folder was selected." -ForegroundColor Red
        Start-Sleep -Seconds 1
        return "menu"
    }

    $targetPaths = @()

    foreach ($key in $Selection) {
        if ($folderMap.Contains($key)) {
            $targetPaths += $folderMap[$key].Path
        }
    }

    if (-not $targetPaths -or $targetPaths.Count -eq 0) {
        Show-Top
        Write-Host "No valid folder was selected." -ForegroundColor Red
        Start-Sleep -Seconds 1
        return "menu"
    }

    $logSettings = Ask-LogSettings
    $startedAt = Get-Date

    Show-Targets -Paths $targetPaths

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($path in $targetPaths) {
        if (Test-Path -LiteralPath $path) {
            Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
                $items.Add($_)
            }
        }
    }

    $total = $items.Count
    $cleaned = 0
    $skipped = 0
    $cleanedBytes = 0L

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
        $percent = [math]::Floor(($current / $total) * 100)

        Write-Progress -Activity "Cleaning files" -Status ("{0}% completed" -f $percent) -PercentComplete $percent

        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)

            if ($key.Key -eq [ConsoleKey]::Spacebar) {
                Write-Progress -Activity "Cleaning files" -Completed

                $pauseChoice = Pause-Menu
                if ($pauseChoice -eq "2") {
                    return "menu"
                }

                Show-Targets -Paths $targetPaths
            }
        }

        try {
            $entrySize = Get-EntrySize -Entry $item
            Remove-OneItem -Entry $item
            $cleaned++
            $cleanedBytes += $entrySize
        }
        catch {
            $skipped++
        }
    }

    Write-Progress -Activity "Cleaning files" -Completed

    if ($cleanMode -eq 3) {
        Empty-Bin
    }

    $finishedAt = Get-Date
    $spaceText = Format-Size -Bytes $cleanedBytes
    $logPath = $null

    if ($logSettings.Enabled) {
        $logPath = Write-CleanupLog `
            -LogFolder $logSettings.Folder `
            -TargetPaths $targetPaths `
            -ModeName (Get-ModeName) `
            -Cleaned $cleaned `
            -Skipped $skipped `
            -SpaceCleaned $spaceText `
            -StartedAt $startedAt `
            -FinishedAt $finishedAt
    }

    Write-Host ""
    Write-Host "Cleanup completed successfully." -ForegroundColor Green
    Write-Host ("Mode: {0}" -f (Get-ModeName)) -ForegroundColor Cyan
    Write-Host ("Cleaned items: {0}" -f $cleaned) -ForegroundColor Green
    Write-Host ("Skipped items: {0}" -f $skipped) -ForegroundColor Yellow
    Write-Host ("Estimated space cleaned: {0}" -f $spaceText) -ForegroundColor Green

    switch ($cleanMode) {
        1 { Write-Host "The cleaned files were sent to the Recycle Bin." -ForegroundColor Green }
        2 { Write-Host "The cleaned files were permanently deleted." -ForegroundColor Green }
        3 { Write-Host "The cleaned files were sent to the Recycle Bin and the Recycle Bin was emptied." -ForegroundColor Green }
    }

    if ($logSettings.Enabled) {
        if ($logPath) {
            Write-Host ("Log saved to: {0}" -f $logPath) -ForegroundColor Cyan
        }
        else {
            Write-Host "The cleanup finished, but the log could not be saved." -ForegroundColor Yellow
        }
    }

    $next = After-CleanupMenu
    switch ($next) {
        "1" { return "rerun" }
        "2" { return "menu" }
        "3" { return "exit" }
    }
}

while ($true) {
    Show-MainMenu
    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" {
            do {
                $selection = Pick-Folders
                $result = Start-Cleaning -Selection $selection
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
                Start-Sleep -Seconds 1
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