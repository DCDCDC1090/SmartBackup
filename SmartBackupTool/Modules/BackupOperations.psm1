# BackupOperations.psm1 - Core backup and restore operations

# Global variable to track current backup operation
$script:CurrentBackupConfig = $null

function Start-BackupOperation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory=$true)]
        [array]$FoldersToBackup,
        
        [string]$DestinationPath,
        
        [scriptblock]$LogFunction = { param($message) Write-Host $message },
        
        [scriptblock]$ProgressFunction = { param($current, $total, $statusMessage) },
        
        [scriptblock]$CompleteFunction = { param($success, $resultPath, $errors) }
    )
    
    # Check if test mode is enabled
    if ($Config.TestModeEnabled) {
        $LogFunction.Invoke("TEST MODE ACTIVE - Simulating backup operation")
        
        # Instead of actual file operations, simulate them
        foreach ($folder in $FoldersToBackup) {
            $srcPath = $folder.Path
            $folderName = Split-Path -Path $srcPath -Leaf
            $targetPath = Join-Path -Path $backupTargetPath -ChildPath $folderName
            
            # Get folder size for simulation
            $folderInfo = Get-FolderSize -FolderPath $srcPath
            
            if ($folderInfo) {
                $result = Simulate-FileOperation -OperationType "Copy" -SourcePath $srcPath -DestinationPath $targetPath -FileSize $folderInfo.Size -IsDirectory $true
                
                Write-TestLog "Simulated backup of folder '$folderName'" -Category "Backup" -Operation "FolderCopy"
                Write-TestLog "  From: $srcPath" -Category "Backup" -Operation "FolderCopy"
                Write-TestLog "  To: $targetPath" -Category "Backup" -Operation "FolderCopy"
                Write-TestLog "  Size: $(Format-FileSize $folderInfo.Size)" -Category "Backup" -Operation "FolderCopy"
                Write-TestLog "  File Count: $($folderInfo.FileCount)" -Category "Backup" -Operation "FolderCopy"
            }
        }
        
        # Create simulated logfiles
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        Write-TestLog "Simulation created logs at: $(Join-Path -Path $backupTargetPath -ChildPath "BackupDetails.log")" -Category "Backup" -Operation "LogCreation"
        
        # Update progress
        $ProgressFunction.Invoke($FoldersToBackup.Count, $FoldersToBackup.Count, "Backup simulation complete")
        
        # Simulate completion
        $CompleteFunction.Invoke($true, $backupTargetPath, @())
        return
    }
    
    # Validate parameters
    if (-not $FoldersToBackup -or $FoldersToBackup.Count -eq 0) {
        $LogFunction.Invoke("No folders selected for backup.")
        $CompleteFunction.Invoke($false, $null, @("No folders selected for backup."))
        return
    }
    
    if (-not $DestinationPath) {
        $DestinationPath = $Config.DefaultBackupRoot
    }
    
    if (-not (Test-Path -Path $DestinationPath -PathType Container)) {
        try {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
            $LogFunction.Invoke("Created destination directory: $DestinationPath")
        }
        catch {
            $LogFunction.Invoke("ERROR: Failed to create destination directory: $_")
            $CompleteFunction.Invoke($false, $null, @("Failed to create destination directory: $_"))
            return
        }
    }
    
    # Set up backup operation
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $finalBackupPath = Join-Path -Path $DestinationPath -ChildPath "Backup_$timestamp"
    $useReviewMode = $Config.EnableReviewMode
    $enableScreenshot = $Config.EnableScreenshot
    $useIncrementalMode = $Config.ProfileSettings.Incremental
    $useCompression = $Config.ProfileSettings.Compression.Enabled
    
    # Set up the target backup path based on review mode
    $backupTargetPath = $null
    $tempBackupRoot = $Config.TempBackupRoot
    
    if ($useReviewMode) {
        if (-not (Test-Path -Path $tempBackupRoot -PathType Container)) {
            try {
                New-Item -Path $tempBackupRoot -ItemType Directory -Force | Out-Null
                $LogFunction.Invoke("Created temporary review directory: $tempBackupRoot")
            }
            catch {
                $LogFunction.Invoke("ERROR: Failed to create temporary directory: $_")
                $CompleteFunction.Invoke($false, $null, @("Failed to create temporary directory: $_"))
                return
            }
        }
        
        $backupTargetPath = Join-Path -Path $tempBackupRoot -ChildPath $timestamp
    }
    else {
        $backupTargetPath = $finalBackupPath
    }
    
    # Create the backup target directory
    try {
        New-Item -Path $backupTargetPath -ItemType Directory -Force | Out-Null
        $LogFunction.Invoke("Created backup target directory: $backupTargetPath")
    }
    catch {
        $LogFunction.Invoke("ERROR: Failed to create backup target directory: $_")
        $CompleteFunction.Invoke($false, $null, @("Failed to create backup target directory: $_"))
        return
    }
    
    # Store current backup configuration for potential async operations
    $script:CurrentBackupConfig = @{
        Config = $Config
        FoldersToBackup = $FoldersToBackup
        DestinationPath = $DestinationPath
        BackupTargetPath = $backupTargetPath
        FinalBackupPath = $finalBackupPath
        UseReviewMode = $useReviewMode
        EnableScreenshot = $enableScreenshot
        UseIncrementalMode = $useIncrementalMode
        UseCompression = $useCompression
        LogFunction = $LogFunction
        ProgressFunction = $ProgressFunction
        CompleteFunction = $CompleteFunction
        Timestamp = $timestamp
        TotalItems = $FoldersToBackup.Count
        CurrentItem = 0
        SkippedItems = @()
        ProcessedItems = @()
        TotalFilesProcessed = 0
        TotalBytesProcessed = 0
        StartTime = Get-Date
    }
    
    # Start backup process
    $LogFunction.Invoke("Starting backup operation...")
    $LogFunction.Invoke("Mode: $($useIncrementalMode ? 'Incremental' : 'Full')")
    $LogFunction.Invoke("Compression: $($useCompression ? 'Enabled' : 'Disabled')")
    
    # Execute the backup process
    # This can be synchronous or asynchronous depending on the implementation
    if ($useIncrementalMode) {
        Invoke-IncrementalBackup
    }
    else {
        Invoke-FullBackup
    }
}

function Invoke-FullBackup {
    [CmdletBinding()]
    param()
    
    $config = $script:CurrentBackupConfig
    if (-not $config) {
        Write-Error "No active backup configuration found."
        return
    }
    
    $LogFunction = $config.LogFunction
    $ProgressFunction = $config.ProgressFunction
    $backupTargetPath = $config.BackupTargetPath
    
    # Tracking variables
    $skippedItems = @()
    $backupDetailsLog = @()
    $totalItems = $config.TotalItems
    $errors = @()
    $operationFailed = $false
    
    # Process each folder
    for ($i = 0; $i -lt $config.FoldersToBackup.Count; $i++) {
        $folderObj = $config.FoldersToBackup[$i]
        $srcPath = $folderObj.Path
        $config.CurrentItem = $i + 1
        
        # Update progress
        $percentComplete = [math]::Round(($config.CurrentItem / $totalItems) * 100)
        $ProgressFunction.Invoke($config.CurrentItem, $totalItems, "Backing up: $srcPath")
        
        # Check if source exists
        if (-not (Test-Path -Path $srcPath -PathType Container)) {
            $errorMessage = "Source path does not exist or is inaccessible: $srcPath"
            $skippedItems += "SKIPPED: $srcPath -> $errorMessage"
            $LogFunction.Invoke("[$($config.CurrentItem)/$totalItems] SKIPPED: $errorMessage")
            $errors += $errorMessage
            $operationFailed = $true
            continue
        }
        
        # Get folder name and sanitize it
        $folderName = Split-Path -Path $srcPath -Leaf
        $invalidChars = [IO.Path]::GetInvalidFileNameChars() -join ''
        $regexInvalidChars = "[{0}]" -f ([RegEx]::Escape($invalidChars))
        $safeFolderName = $folderName -replace $regexInvalidChars, '_'
        
        if ($safeFolderName -ne $folderName) {
            $LogFunction.Invoke("Note: Sanitized folder name from '$folderName' to '$safeFolderName'")
        }
        
        $targetPath = Join-Path -Path $backupTargetPath -ChildPath $safeFolderName
        $backupDetailsLog += "[(:$($i+1))]$safeFolderName - Location - [(:$($i+1))]$srcPath"
        
        $LogFunction.Invoke("[$($config.CurrentItem)/$totalItems] Backing up: $srcPath")
        
        # Perform the actual copy
        try {
            # Determine whether to use compression
            if ($config.UseCompression) {
                # Compress folder will be handled by the Compression module
                $compressionLevel = $config.Config.ProfileSettings.Compression.Level
                $compressionResult = Compress-Folder -SourcePath $srcPath -DestinationPath $targetPath -CompressionLevel $compressionLevel
                
                if ($compressionResult.Success) {
                    $LogFunction.Invoke("  -> OK (Compressed): $targetPath")
                    $config.TotalFilesProcessed += $compressionResult.FileCount
                    $config.TotalBytesProcessed += $compressionResult.ByteCount
                }
                else {
                    throw $compressionResult.ErrorMessage
                }
            }
            else {
                # Regular copy
                $sourceItem = Get-Item -Path $srcPath
                
                # Get file count for statistics
                $fileCount = (Get-ChildItem -Path $srcPath -Recurse -File -ErrorAction SilentlyContinue).Count
                $byteCount = (Get-ChildItem -Path $srcPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                
                Copy-Item -Path $srcPath -Destination $targetPath -Recurse -Force -ErrorAction Stop
                $LogFunction.Invoke("  -> OK: $targetPath")
                
                $config.TotalFilesProcessed += $fileCount
                $config.TotalBytesProcessed += $byteCount
            }
            
            $config.ProcessedItems += $targetPath
        }
        catch {
            $errorMessage = $_.Exception.Message -replace '[\r\n]', ' '
            $skippedItems += "$srcPath -> $targetPath : $errorMessage"
            $LogFunction.Invoke("  -> ERROR: $errorMessage")
            $errors += $errorMessage
            $operationFailed = $true
        }
    }
    
    # Write log files
    try {
        # Skipped items log
        if ($skippedItems.Count -gt 0) {
            $skippedLogPath = Join-Path -Path $backupTargetPath -ChildPath "SkippedItems.log"
            Set-Content -Path $skippedLogPath -Value $skippedItems -Encoding UTF8
            $LogFunction.Invoke("Created skipped items log: $skippedLogPath")
        }
        
        # Backup details log (sorted and renumbered)
        if ($backupDetailsLog.Count -gt 0) {
            $sortedDetails = $backupDetailsLog | Sort-Object { ($_ -replace '^\[\(:\d+\)\](.*?) -.*', '$1').ToLower() }
            $renumberedDetails = for ($j = 0; $j -lt $sortedDetails.Count; $j++) {
                $num = $j + 1
                $line = $sortedDetails[$j]
                # Replace both number instances using regex for safety
                $line -replace '^\[\(:(\d+)\)\]', "[(:$num)]" -replace '-\s\[\(:(\d+)\)\]', "- [(:$num)]"
            }
            
            $detailsLogPath = Join-Path -Path $backupTargetPath -ChildPath "BackupDetails.log"
            Set-Content -Path $detailsLogPath -Value $renumberedDetails -Encoding UTF8
            $LogFunction.Invoke("Created backup details log: $detailsLogPath")
        }
        else {
            $LogFunction.Invoke("No items were successfully backed up to write to details log.")
            $operationFailed = $true
        }
    }
    catch {
        $LogFunction.Invoke("ERROR writing log files: $_")
        $errors += "Failed to write log files: $_"
        $operationFailed = $true
    }
    
    # Calculate statistics
    $elapsedTime = (Get-Date) - $config.StartTime
    $elapsedFormatted = "{0:D2}:{1:D2}:{2:D2}" -f $elapsedTime.Hours, $elapsedTime.Minutes, $elapsedTime.Seconds
    
    # Format byte count in human-readable form
    $bytesProcessed = $config.TotalBytesProcessed
    $sizeFormatted = if ($bytesProcessed -gt 1GB) {
        "{0:N2} GB" -f ($bytesProcessed / 1GB)
    }
    elseif ($bytesProcessed -gt 1MB) {
        "{0:N2} MB" -f ($bytesProcessed / 1MB)
    }
    elseif ($bytesProcessed -gt 1KB) {
        "{0:N2} KB" -f ($bytesProcessed / 1KB)
    }
    else {
        "$bytesProcessed bytes"
    }
    
    $LogFunction.Invoke("--------------------------------------------------")
    $LogFunction.Invoke("Backup operation completed in $elapsedFormatted")
    $LogFunction.Invoke("Files processed: $($config.TotalFilesProcessed)")
    $LogFunction.Invoke("Total size: $sizeFormatted")
    
    # Handle review mode if enabled
    $finalBackupPath = $config.FinalBackupPath
    $backupTargetPath = $config.BackupTargetPath
    $backupKept = $false
    
    if ($config.UseReviewMode) {
        # Return control to caller to handle review confirmation
        # We'll store the current state for review completion later
        $config.OperationFailed = $operationFailed
        $config.Errors = $errors
        $config.SkippedItems = $skippedItems
        
        # The caller should call Complete-ReviewBackup after user confirmation
        return
    }
    else {
        # Backup is already in final location
        $finalPath = $backupTargetPath
        $backupKept = $true
        
        # Take screenshot if enabled
        if ($backupKept -and $config.EnableScreenshot) {
            $LogFunction.Invoke("Taking screenshot...")
            $screenshotPath = Join-Path -Path $finalPath -ChildPath "DesktopScreenshot_$($config.Timestamp).png"
            Capture-DesktopScreenshot -OutputPath $screenshotPath -MinimizeWindows
        }
        
        # Notify completion
        $config.CompleteFunction.Invoke(-not $operationFailed, $finalPath, $errors)
    }
}

function Complete-ReviewBackup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [bool]$KeepBackup
    )
    
    $config = $script:CurrentBackupConfig
    if (-not $config) {
        Write-Error "No active backup review to complete."
        return $false
    }
    
    $LogFunction = $config.LogFunction
    $finalBackupPath = $config.FinalBackupPath
    $backupTargetPath = $config.BackupTargetPath
    $operationFailed = $config.OperationFailed
    $errors = $config.Errors
    
    $backupKept = $false
    $finalPath = $null
    
    if ($KeepBackup) {
        $LogFunction.Invoke("Moving backup from temporary to final location: $finalBackupPath")
        
        try {
            # Ensure final destination parent exists
            $finalParent = Split-Path -Path $finalBackupPath -Parent
            if (-not (Test-Path -Path $finalParent -PathType Container)) {
                New-Item -Path $finalParent -ItemType Directory -Force | Out-Null
            }
            
            # Check if final path already exists
            if (Test-Path -Path $finalBackupPath -PathType Container) {
                throw "Final backup path '$finalBackupPath' already exists. Cannot move."
            }
            
            # Move the backup to its final location
            Move-Item -Path $backupTargetPath -Destination $finalBackupPath -Force
            $LogFunction.Invoke("Move successful.")
            $finalPath = $finalBackupPath
            $backupKept = $true
        }
        catch {
            $LogFunction.Invoke("ERROR moving backup: $_")
            $errors += "Failed to move backup to final location: $_"
            $operationFailed = $true
            $finalPath = $backupTargetPath
            $backupKept = $true # Still mark as kept so we can take screenshot
        }
    }
    else {
        $LogFunction.Invoke("Discarding temporary backup: $backupTargetPath")
        
        try {
            # Remove the temporary backup folder
            Remove-Item -Path $backupTargetPath -Recurse -Force
            $LogFunction.Invoke("Temporary backup deleted.")
            $backupKept = $false
            $finalPath = $null
        }
        catch {
            $LogFunction.Invoke("ERROR deleting temporary backup: $_")
            $errors += "Failed to delete temporary backup: $_"
            # Don't mark operation as failed just because temp cleanup failed
        }
    }
    
    # Take screenshot if enabled and backup was kept
    if ($backupKept -and $config.EnableScreenshot -and $finalPath) {
        $LogFunction.Invoke("Taking screenshot...")
        $screenshotPath = Join-Path -Path $finalPath -ChildPath "DesktopScreenshot_$($config.Timestamp).png"
        Capture-DesktopScreenshot -OutputPath $screenshotPath -MinimizeWindows
    }
    
    # Clean up temporary directory if empty
    if ($backupKept -and (Test-Path -Path $config.Config.TempBackupRoot -PathType Container)) {
        try {
            $remainingItems = Get-ChildItem -Path $config.Config.TempBackupRoot -Force
            if (-not $remainingItems -or $remainingItems.Count -eq 0) {
                $LogFunction.Invoke("Removing empty temporary backup root directory...")
                Remove-Item -Path $config.Config.TempBackupRoot -Force
            }
        }
        catch {
            $LogFunction.Invoke("Warning: Could not clean up temporary directory: $_")
        }
    }
    
    # Notify completion
    $config.CompleteFunction.Invoke(-not $operationFailed, $finalPath, $errors)
    
    # Reset current backup config
    $script:CurrentBackupConfig = $null
    
    return -not $operationFailed
}

function Start-RestoreOperation {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupPath,
        
        [Parameter(Mandatory=$true)]
        [array]$ItemsToRestore,
        
        [bool]$TestMode = $false,
        
        [scriptblock]$LogFunction = { param($message) Write-Host $message },
        
        [scriptblock]$ProgressFunction = { param($current, $total, $statusMessage) },
        
        [scriptblock]$CompleteFunction = { param($success, $errors) }
    )
    
    # Check for test mode at application level (overrides parameter)
    if ($script:config -and $script:config.TestModeEnabled) {
        $TestMode = $true
        $LogFunction.Invoke("TEST MODE ACTIVE - Simulating restore operation")
        
        # Simulate the restore process
        foreach ($item in $ItemsToRestore) {
            if (-not $item.Checked) { continue }
            
            $sourcePath = $item.SourcePath
            $targetPath = $item.OriginalPath
            
            Write-TestLog "Simulating restore of: $($item.Name)" -Category "Restore" -Operation "FolderRestore"
            Write-TestLog "  Source: $sourcePath" -Category "Restore" -Operation "FolderRestore"
            Write-TestLog "  Target: $targetPath" -Category "Restore" -Operation "FolderRestore"
            
            # Get source folder info for simulation
            $folderInfo = Get-FolderSize -FolderPath $sourcePath
            if ($folderInfo) {
                Write-TestLog "  Size: $(Format-FileSize $folderInfo.Size)" -Category "Restore" -Operation "FolderRestore"
                Write-TestLog "  File Count: $($folderInfo.FileCount)" -Category "Restore" -Operation "FolderRestore"
                
                # Simulate file operations
                Simulate-FileOperation -OperationType "Restore" -SourcePath $sourcePath -DestinationPath $targetPath -FileSize $folderInfo.Size -IsDirectory $true
            }
        }
        
        # Simulate logs
        Write-TestLog "Restore simulation complete - $($ItemsToRestore.Count) folders simulated" -Category "Restore" -Operation "Summary"
        
        # Call completion
        $CompleteFunction.Invoke($true, @())
        return $true
    }
    
    # Validate parameters
    if (-not (Test-Path -Path $BackupPath -PathType Container)) {
        $LogFunction.Invoke("ERROR: Backup source directory does not exist: $BackupPath")
        $CompleteFunction.Invoke($false, @("Backup source directory does not exist: $BackupPath"))
        return
    }
    
    if (-not $ItemsToRestore -or $ItemsToRestore.Count -eq 0) {
        $LogFunction.Invoke("No items selected for restore.")
        $CompleteFunction.Invoke($false, @("No items selected for restore."))
        return
    }
    
    # Log operation start
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $LogFunction.Invoke("Starting restore operation at $timestamp")
    $LogFunction.Invoke("Source: $BackupPath")
    $LogFunction.Invoke("Mode: $($TestMode ? 'Simulation (no files will be modified)' : 'Actual restore')")
    
    # Check if detail log exists for validation
    $detailsLogPath = Join-Path -Path $BackupPath -ChildPath "BackupDetails.log"
    if (-not (Test-Path -Path $detailsLogPath -PathType Leaf)) {
        $LogFunction.Invoke("WARNING: BackupDetails.log not found in backup source.")
    }
    
    # Initialize tracking variables
    $totalItems = $ItemsToRestore.Count
    $currentItem = 0
    $errors = @()
    $successItems = @()
    $skippedItems = @()
    $operationFailed = $false
    $startTime = Get-Date
    
    # Set up log files
    $logBase = Split-Path -Path $BackupPath -Parent
    $backupName = Split-Path -Path $BackupPath -Leaf
    $restoreDetailsLogPath = Join-Path -Path $logBase -ChildPath "RestoreDetails_${backupName}_$timestamp.log"
    $skippedRestoreLogPath = Join-Path -Path $logBase -ChildPath "SkippedRestoreItems_${backupName}_$timestamp.log"
    $testModeLogPath = Join-Path -Path $logBase -ChildPath "TestRestoreSimulation_${backupName}_$timestamp.log"
    
    # Process each restore item
    foreach ($item in $ItemsToRestore) {
        $currentItem++
        
        # Skip items that are not checked for restore
        if (-not $item.Checked) {
            $skippedItems += "SKIPPED (User Unchecked): $($item.Name) -> $($item.OriginalPath)"
            continue
        }
        
        $sourcePath = $item.SourcePath # Path in the backup
        $targetPath = $item.OriginalPath # Original path to restore to
        
        $percentComplete = [math]::Round(($currentItem / $totalItems) * 100)
        $ProgressFunction.Invoke($currentItem, $totalItems, "Restoring: $($item.Name)")
        
        $LogFunction.Invoke("[$currentItem/$totalItems] Processing: $($item.Name) -> $targetPath")
        
        $itemSkipped = $false
        $skipReason = ""
        
        # Pre-checks
        if (-not (Test-Path -Path $sourcePath -PathType Container)) {
            $itemSkipped = $true
            $skipReason = "Source in backup is not a valid directory: $sourcePath"
            $operationFailed = $true
        }
        elseif (-not $TestMode) {
            # In non-test mode, ensure target parent directory exists
            $targetParent = Split-Path -Path $targetPath -Parent
            
            if ($targetParent -and (-not (Test-Path -Path $targetParent -PathType Container))) {
                # Attempt to create parent directory
                $LogFunction.Invoke("  Target parent directory missing, attempting to create: $targetParent")
                
                try {
                    New-Item -Path $targetParent -ItemType Directory -Force | Out-Null
                    $LogFunction.Invoke("  -> Parent directory created.")
                }
                catch {
                    $itemSkipped = $true
                    $skipReason = "Failed to create target parent directory '$targetParent': $($_.Exception.Message -replace '[\r\n]',' ')"
                    $operationFailed = $true
                }
            }
        }
        
        # Perform the restore operation if no pre-check failures
        if (-not $itemSkipped) {
            if ($TestMode) {
                $logEntry = "TEST MODE: Would restore '$sourcePath' to '$targetPath'"
                $LogFunction.Invoke("  -> $logEntry")
                $successItems += "$($item.Name) -> $targetPath (Simulated)"
            }
            else {
                try {
                    # Check if target exists and remove it if needed
                    if (Test-Path -Path $targetPath) {
                        $LogFunction.Invoke("  Target '$targetPath' exists. Removing before copy.")
                        Remove-Item -Path $targetPath -Recurse -Force
                    }
                    
                    # Copy from backup to original location
                    Copy-Item -Path $sourcePath -Destination $targetPath -Recurse -Force
                    $LogFunction.Invoke("  -> OK: Restored to $targetPath")
                    $successItems += "$($item.Name) -> $targetPath"
                }
                catch {
                    $itemSkipped = $true
                    $skipReason = "Error restoring '$sourcePath' to '$targetPath': $($_.Exception.Message -replace '[\r\n]',' ')"
                    $operationFailed = $true
                    $errors += $skipReason
                }
            }
        }
        
        # Add to skipped log if needed
        if ($itemSkipped) {
            $skippedItems += "SKIPPED ($($item.Name) -> $targetPath): $skipReason"
            $LogFunction.Invoke("  -> SKIPPED: $skipReason")
        }
    }
    
    # Write log files
    try {
        # Restore Details Log
        if ($successItems.Count -gt 0) {
            Set-Content -Path $restoreDetailsLogPath -Value $successItems -Encoding UTF8
            $LogFunction.Invoke("Created restore details log: $restoreDetailsLogPath")
        }
        
        # Skipped Restore Log
        if ($skippedItems.Count -gt 0) {
            Set-Content -Path $skippedRestoreLogPath -Value $skippedItems -Encoding UTF8
            $LogFunction.Invoke("Created skipped restore items log: $skippedRestoreLogPath")
        }
        
        # Test Mode Simulation Log
        if ($TestMode -and $successItems.Count -gt 0) {
            $testLogHeader = @(
                "--- TEST MODE RESTORE SIMULATION ---",
                "Timestamp: $(Get-Date)",
                "Source Backup: $BackupPath",
                "------------------------------------"
            )
            
            Set-Content -Path $testModeLogPath -Value ($testLogHeader + $successItems) -Encoding UTF8
            $LogFunction.Invoke("Created test mode simulation log: $testModeLogPath")
        }
    }
    catch {
        $LogFunction.Invoke("WARNING: Error writing log files: $_")
    }
    
    # Calculate statistics
    $elapsedTime = (Get-Date) - $startTime
    $elapsedFormatted = "{0:D2}:{1:D2}:{2:D2}" -f $elapsedTime.Hours, $elapsedTime.Minutes, $elapsedTime.Seconds
    
    $LogFunction.Invoke("--------------------------------------------------")
    $LogFunction.Invoke("Restore operation completed in $elapsedFormatted")
    $LogFunction.Invoke("Items successfully processed: $($successItems.Count)")
    $LogFunction.Invoke("Items skipped: $($skippedItems.Count)")
    
    # Notify completion
    $CompleteFunction.Invoke(-not $operationFailed, $errors)
    
    return -not $operationFailed
}

function Get-RestoreFolderList {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$BackupPath
    )
    
    # Check if the backup path exists
    if (-not (Test-Path -Path $BackupPath -PathType Container)) {
        Write-Error "Backup path not found: $BackupPath"
        return $null
    }
    
    # Check for BackupDetails.log
    $detailsLogPath = Join-Path -Path $BackupPath -ChildPath "BackupDetails.log"
    if (-not (Test-Path -Path $detailsLogPath -PathType Leaf)) {
        Write-Warning "BackupDetails.log not found in: $BackupPath"
        return $null
    }
    
    # Read backup details
    $folderList = @()
    
    try {
        $logContent = Get-Content -Path $detailsLogPath -Encoding UTF8
        
        foreach ($line in $logContent) {
            if ($line -match '^\[\(:(\d+)\)\](.*?)\s+-\s+Location\s+-\s+\[\(:(\d+)\)\](.*)$') {
                $name = $matches[2].Trim()
                $originalPath = $matches[4].Trim()
                
                # Check if the folder exists in the backup
                $sourceFolderPath = Join-Path -Path $BackupPath -ChildPath $name
                
                if (Test-Path -Path $sourceFolderPath -PathType Container) {
                    $folderList += [PSCustomObject]@{
                        Name = $name
                        OriginalPath = $originalPath
                        SourcePath = $sourceFolderPath
                        Checked = $true
                    }
                }
            }
        }
    }
    catch {
        Write-Error "Error reading BackupDetails.log: $_"
        return $null
    }
    
    return $folderList
}

function Start-AutomatedBackup {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config,
        
        [string]$LogFilePath
    )
    
    # Setup logging
    if (-not $LogFilePath) {
        $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
        $logDir = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "logs"
        
        if (-not (Test-Path -Path $logDir -PathType Container)) {
            New-Item -Path $logDir -ItemType Directory -Force | Out-Null
        }
        
        $LogFilePath = Join-Path -Path $logDir -ChildPath "AutoBackup_$timestamp.log"
    }
    
    # Start transcript for logging
    Start-Transcript -Path $LogFilePath -Append
    
    # Define log function that writes to console and transcript
    $logFunction = {
        param($message)
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Write-Host "[$timestamp] $message"
    }
    
    $logFunction.Invoke("Starting automated backup using profile: $($Config.CurrentProfileName)")
    
    # Load folder list
    $folderList = @()
    
    # Check for custom folders saved in config
    if ($Config.CustomFoldersList -and $Config.CustomFoldersList.Count -gt 0) {
        foreach ($folder in $Config.CustomFoldersList) {
            if ($folder.Default -and $folder.Path -and (Test-Path -Path $folder.Path -PathType Container)) {
                $folderList += $folder
            }
        }
    }
    
    # Add known backup folders if custom list is empty
    if ($folderList.Count -eq 0) {
        $knownFolders = Get-KnownBackupFolders
        
        foreach ($folder in $knownFolders) {
            $folderList += [PSCustomObject]@{
                Path = $folder
                Checked = $true
                Default = $true
            }
        }
        
        # Add Firefox profile unless disabled
        if (-not $Config.DisableFirefoxBackup) {
            $firefoxProfile = Get-FirefoxProfilePath
            
            if ($firefoxProfile -and (Test-Path -Path $firefoxProfile -PathType Container)) {
                $folderList += [PSCustomObject]@{
                    Path = $firefoxProfile
                    Checked = $true
                    Default = $true
                }
            }
        }
    }
    
    # Check if we have folders to back up
    if ($folderList.Count -eq 0) {
        $logFunction.Invoke("ERROR: No folders found for backup.")
        Stop-Transcript
        return $false
    }
    
    $logFunction.Invoke("Found $($folderList.Count) folders to back up.")
    
    # Define progress function
    $progressFunction = {
        param($current, $total, $statusMessage)
        $percent = [math]::Round(($current / $total) * 100)
        $logFunction.Invoke("Progress: $percent% - $statusMessage")
    }
    
    # Define completion function
    $completeFunction = {
        param($success, $resultPath, $errors)
        
        if ($success) {
            $logFunction.Invoke("Backup completed successfully.")
            $logFunction.Invoke("Backup location: $resultPath")
        }
        else {
            $logFunction.Invoke("Backup completed with errors.")
            
            if ($errors -and $errors.Count -gt 0) {
                $logFunction.Invoke("Errors encountered:")
                foreach ($error in $errors) {
                    $logFunction.Invoke(" - $error")
                }
            }
            
            if ($resultPath) {
                $logFunction.Invoke("Partial backup location: $resultPath")
            }
        }
    }
    
    # Start the backup
    $backupResult = Start-BackupOperation -Config $Config `
                                         -FoldersToBackup $folderList `
                                         -DestinationPath $Config.DefaultBackupRoot `
                                         -LogFunction $logFunction `
                                         -ProgressFunction $progressFunction `
                                         -CompleteFunction $completeFunction
    
    # In automated mode, always keep the backup (no review)
    if ($Config.EnableReviewMode) {
        $logFunction.Invoke("Auto-accepting backup in review mode.")
        Complete-ReviewBackup -KeepBackup $true
    }
    
    $logFunction.Invoke("Automated backup process completed.")
    Stop-Transcript
    
    return $backupResult
}

# Helper function for test mode
function Format-FileSize {
    param ([long]$Size)
    
    if ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size / 1GB) }
    elseif ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size / 1MB) }
    elseif ($Size -gt 1KB) { return "{0:N2} KB" -f ($Size / 1KB) }
    else { return "$Size bytes" }
}

# Export module functions
Export-ModuleMember -Function Start-BackupOperation, 
                              Complete-ReviewBackup, 
                              Start-RestoreOperation, 
                              Get-RestoreFolderList, 
                              Start-AutomatedBackup,
                              Format-FileSize