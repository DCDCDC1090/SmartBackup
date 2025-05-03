# IncrementalBackup.psm1 - Incremental backup tracking functionality

function Invoke-IncrementalBackup {
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
    
    # Create special marker file to indicate this is an incremental backup
    $incrementalInfoPath = Join-Path -Path $backupTargetPath -ChildPath ".incremental_info.json"
    $incrementalInfo = @{
        Type = "Incremental"
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        PreviousBackups = @()
    }
    
    # Find previous backups
    $lastFullBackup = $null
    $lastIncrementalBackup = $null
    
    # Check if there's a previous backup by scanning the backup root directory
    $backupRoot = Split-Path -Path $config.FinalBackupPath -Parent
    $previousBackups = Get-ChildItem -Path $backupRoot -Directory |
                       Where-Object { $_.Name -match '^Backup_\d{4}-\d{2}-\d{2}' } |
                       Sort-Object -Property LastWriteTime -Descending
    
    foreach ($prevBackup in $previousBackups) {
        $incrementalInfoFile = Join-Path -Path $prevBackup.FullName -ChildPath ".incremental_info.json"
        
        if (Test-Path -Path $incrementalInfoFile -PathType Leaf) {
            try {
                $prevInfo = Get-Content -Path $incrementalInfoFile -Raw | ConvertFrom-Json
                
                if ($prevInfo.Type -eq "Incremental") {
                    if (-not $lastIncrementalBackup) {
                        $lastIncrementalBackup = $prevBackup.FullName
                        $incrementalInfo.PreviousBackups += $prevBackup.FullName
                    }
                }
            }
            catch {
                $LogFunction.Invoke("Warning: Could not read incremental info from $($prevBackup.FullName): $_")
            }
        }
        elseif (-not $lastFullBackup) {
            # Assume it's a full backup if no incremental info file
            $lastFullBackup = $prevBackup.FullName
            $incrementalInfo.PreviousBackups += $prevBackup.FullName
        }
        
        # Once we have both a full and incremental backup (or reached max references), we can stop looking
        if ($lastFullBackup -and ($lastIncrementalBackup -or $incrementalInfo.PreviousBackups.Count -ge 5)) {
            break
        }
    }
    
    # Store database info
    $backupDatabase = @{}
    $manifestPath = Join-Path -Path $backupTargetPath -ChildPath ".backup_manifest.json"
    
    # Tracking variables
    $skippedItems = @()
    $backupDetailsLog = @()
    $totalItems = $config.TotalItems
    $errors = @()
    $operationFailed = $false
    $newFileCount = 0
    $unchangedFileCount = 0
    $totalBytesProcessed = 0
    
    # Process each folder
    for ($i = 0; $i -lt $config.FoldersToBackup.Count; $i++) {
        $folderObj = $config.FoldersToBackup[$i]
        $srcPath = $folderObj.Path
        $config.CurrentItem = $i + 1
        
        # Update progress
        $percentComplete = [math]::Round(($config.CurrentItem / $totalItems) * 100)
        $ProgressFunction.Invoke($config.CurrentItem, $totalItems, "Analyzing: $srcPath")
        
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
        
        $LogFunction.Invoke("[$($config.CurrentItem)/$totalItems] Analyzing: $srcPath")
        
        # Create target directory
        if (-not (Test-Path -Path $targetPath -PathType Container)) {
            try {
                New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
            }
            catch {
                $errorMessage = $_.Exception.Message -replace '[\r\n]', ' '
                $skippedItems += "$srcPath -> $targetPath : $errorMessage"
                $LogFunction.Invoke("  -> ERROR: Failed to create target directory: $errorMessage")
                $errors += $errorMessage
                $operationFailed = $true
                continue
            }
        }
        
        # Initialize folder database entry
        $backupDatabase[$safeFolderName] = @{
            SourcePath = $srcPath
            Files = @{}
        }
        
        # Get source files
        $files = Get-ChildItem -Path $srcPath -Recurse -File -ErrorAction SilentlyContinue
        $fileCount = $files.Count
        $currentFile = 0
        
        $LogFunction.Invoke("  Found $fileCount files to process.")
        
        # Process each file
        foreach ($file in $files) {
            $currentFile++
            
            # Update file progress periodically
            if ($currentFile % 100 -eq 0 -or $currentFile -eq $fileCount) {
                $fileProgress = [math]::Round(($currentFile / $fileCount) * 100)
                $ProgressFunction.Invoke($config.CurrentItem, $totalItems, "Processing files in $safeFolderName ($fileProgress%)")
            }
            
            # Calculate relative path
            $relativePath = $file.FullName.Substring($srcPath.Length).TrimStart('\', '/')
            
            # Generate file hash for change detection
            $fileHash = Get-FileHash -FilePath $file.FullName -Algorithm "MD5"
            
            # Store file info in database
            $backupDatabase[$safeFolderName].Files[$relativePath] = @{
                Hash = $fileHash
                Size = $file.Length
                LastModified = $file.LastWriteTime.ToString("o")
                BackupPath = $null # Will be set if copied
            }
            
            # Check if the file has changed by looking in previous backups
            $fileChanged = $true
            
            # Search in previous backups for matching hash
            foreach ($prevBackupPath in $incrementalInfo.PreviousBackups) {
                $prevFolderPath = Join-Path -Path $prevBackupPath -ChildPath $safeFolderName
                $prevFilePath = Join-Path -Path $prevFolderPath -ChildPath $relativePath
                
                if (Test-Path -Path $prevFilePath -PathType Leaf) {
                    $prevFileHash = Get-FileHash -FilePath $prevFilePath -Algorithm "MD5"
                    
                    if ($prevFileHash -eq $fileHash) {
                        # File exists in previous backup with same hash
                        $backupDatabase[$safeFolderName].Files[$relativePath].BackupPath = "REF:$prevBackupPath:$safeFolderName:$relativePath"
                        $fileChanged = $false
                        $unchangedFileCount++
                        break
                    }
                }
            }
            
            # Copy file if changed
            if ($fileChanged) {
                $destFilePath = Join-Path -Path $targetPath -ChildPath $relativePath
                $destFileDir = Split-Path -Path $destFilePath -Parent
                
                if (-not (Test-Path -Path $destFileDir -PathType Container)) {
                    try {
                        New-Item -Path $destFileDir -ItemType Directory -Force | Out-Null
                    }
                    catch {
                        $LogFunction.Invoke("  -> ERROR: Failed to create directory for $relativePath: $_")
                        continue
                    }
                }
                
                try {
                    Copy-Item -Path $file.FullName -Destination $destFilePath -Force
                    $backupDatabase[$safeFolderName].Files[$relativePath].BackupPath = "LOCAL:$relativePath"
                    $newFileCount++
                    $totalBytesProcessed += $file.Length
                }
                catch {
                    $LogFunction.Invoke("  -> ERROR: Failed to copy $relativePath: $_")
                }
            }
        }
        
        $LogFunction.Invoke("  Added $($newFileCount - ($config.TotalFilesProcessed)) new files, referenced $($unchangedFileCount - ($config.TotalFilesProcessed - $newFileCount)) unchanged files.")
    }
    
    # Update counts in config
    $config.TotalFilesProcessed = $newFileCount + $unchangedFileCount
    $config.TotalBytesProcessed = $totalBytesProcessed
    
    # Save manifest and incremental info
    try {
        $backupDatabase | ConvertTo-Json -Depth 10 | Set-Content -Path $manifestPath -Encoding UTF8
        $incrementalInfo | ConvertTo-Json -Depth 5 | Set-Content -Path $incrementalInfoPath -Encoding UTF8
        $LogFunction.Invoke("Created backup manifest file.")
    }
    catch {
        $LogFunction.Invoke("ERROR: Failed to save backup manifest: $_")
        $errors += "Failed to save backup manifest: $_"
        $operationFailed = $true
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
    
    # Log statistics
    $LogFunction.Invoke("--------------------------------------------------")
    $LogFunction.Invoke("Incremental backup operation completed in $elapsedFormatted")
    $LogFunction.Invoke("New files copied: $newFileCount")
    $LogFunction.Invoke("Unchanged files referenced: $unchangedFileCount")
    $LogFunction.Invoke("New data size: $sizeFormatted")
    
    # Handle review mode or complete the backup
    $finalBackupPath = $config.FinalBackupPath
    $backupTargetPath = $config.BackupTargetPath
    $backupKept = $false
    
    if ($config.UseReviewMode) {
        # Return control to caller to handle review confirmation
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

function Restore-IncrementalBackup {
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
    
    # Check if this is an incremental backup
    $incrementalInfoPath = Join-Path -Path $BackupPath -ChildPath ".incremental_info.json"
    if (-not (Test-Path -Path $incrementalInfoPath -PathType Leaf)) {
        $LogFunction.Invoke("This doesn't appear to be an incremental backup. Using standard restore.")
        return Start-RestoreOperation -BackupPath $BackupPath `
                                    -ItemsToRestore $ItemsToRestore `
                                    -TestMode $TestMode `
                                    -LogFunction $LogFunction `
                                    -ProgressFunction $ProgressFunction `
                                    -CompleteFunction $CompleteFunction
    }
    
    # Read incremental info
    try {
        $incrementalInfo = Get-Content -Path $incrementalInfoPath -Raw | ConvertFrom-Json
    }
    catch {
        $LogFunction.Invoke("ERROR: Failed to read incremental info: $_")
        $CompleteFunction.Invoke($false, @("Failed to read incremental info: $_"))
        return $false
    }
    
    # Read backup manifest
    $manifestPath = Join-Path -Path $BackupPath -ChildPath ".backup_manifest.json"
    if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
        $LogFunction.Invoke("ERROR: Backup manifest not found.")
        $CompleteFunction.Invoke($false, @("Backup manifest not found."))
        return $false
    }
    
    try {
        $backupManifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        $LogFunction.Invoke("ERROR: Failed to read backup manifest: $_")
        $CompleteFunction.Invoke($false, @("Failed to read backup manifest: $_"))
        return $false
    }
    
    # Initialize tracking variables
    $totalItems = $ItemsToRestore.Count
    $currentItem = 0
    $errors = @()
    $successItems = @()
    $skippedItems = @()
    $operationFailed = $false
    $startTime = Get-Date
    
    # Process each restore item
    foreach ($item in $ItemsToRestore) {
        $currentItem++
        
        # Skip items that are not checked for restore
        if (-not $item.Checked) {
            $skippedItems += "SKIPPED (User Unchecked): $($item.Name) -> $($item.OriginalPath)"
            continue
        }
        
        $sourceFolderName = $item.Name
        $targetPath = $item.OriginalPath
        
        $percentComplete = [math]::Round(($currentItem / $totalItems) * 100)
        $ProgressFunction.Invoke($currentItem, $totalItems, "Restoring: $sourceFolderName")
        
        $LogFunction.Invoke("[$currentItem/$totalItems] Processing: $sourceFolderName -> $targetPath")
        
        # Check if folder exists in manifest
        if (-not $backupManifest.PSObject.Properties.Name.Contains($sourceFolderName)) {
            $skippedItems += "SKIPPED: $sourceFolderName - Not found in backup manifest."
            $LogFunction.Invoke("  -> SKIPPED: Not found in backup manifest.")
            $operationFailed = $true
            continue
        }
        
        # Create target directory if needed (unless in test mode)
        if (-not $TestMode) {
            if (-not (Test-Path -Path $targetPath -PathType Container)) {
                try {
                    New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
                    $LogFunction.Invoke("  Created target directory: $targetPath")
                }
                catch {
                    $skippedItems += "SKIPPED: $sourceFolderName -> $targetPath - Failed to create target directory: $_"
                    $LogFunction.Invoke("  -> SKIPPED: Failed to create target directory: $_")
                    $operationFailed = $true
                    continue
                }
            }
        }
        
        # Get folder info from manifest
        $folderInfo = $backupManifest.$sourceFolderName
        
        # Get files to restore
        $filesToRestore = $folderInfo.Files.PSObject.Properties
        $fileCount = $filesToRestore.Count
        $currentFile = 0
        
        $LogFunction.Invoke("  Found $fileCount files to restore.")
        
        # Process each file
        foreach ($fileProperty in $filesToRestore) {
            $currentFile++
            
            # Update file progress periodically
            if ($currentFile % 100 -eq 0 -or $currentFile -eq $fileCount) {
                $fileProgress = [math]::Round(($currentFile / $fileCount) * 100)
                $ProgressFunction.Invoke($currentItem, $totalItems, "Restoring files in $sourceFolderName ($fileProgress%)")
            }
            
            $relativePath = $fileProperty.Name
            $fileInfo = $fileProperty.Value
            $backupPath = $fileInfo.BackupPath
            
            if (-not $backupPath) {
                $LogFunction.Invoke("  -> WARNING: No backup path found for $relativePath")
                continue
            }
            
            $destFilePath = Join-Path -Path $targetPath -ChildPath $relativePath
            $destFileDir = Split-Path -Path $destFilePath -Parent
            
            # Create destination directory if needed (unless in test mode)
            if (-not $TestMode) {
                if (-not (Test-Path -Path $destFileDir -PathType Container)) {
                    try {
                        New-Item -Path $destFileDir -ItemType Directory -Force | Out-Null
                    }
                    catch {
                        $LogFunction.Invoke("  -> ERROR: Failed to create directory for $relativePath: $_")
                        continue
                    }
                }
            }
            
            # Process file based on backup path type
            if ($backupPath.StartsWith("LOCAL:")) {
                # File is in the current backup
                $localPath = $backupPath.Substring(6) # Remove "LOCAL:" prefix
                $sourcePath = Join-Path -Path (Join-Path -Path $BackupPath -ChildPath $sourceFolderName) -ChildPath $localPath
                
                if ($TestMode) {
                    $LogFunction.Invoke("  [TEST] Would restore: $relativePath")
                }
                else {
                    try {
                        Copy-Item -Path $sourcePath -Destination $destFilePath -Force
                        $LogFunction.Invoke("  Restored: $relativePath")
                    }
                    catch {
                        $LogFunction.Invoke("  -> ERROR: Failed to restore $relativePath: $_")
                    }
                }
            }
            elseif ($backupPath.StartsWith("REF:")) {
                # File is referenced from a previous backup
                $refParts = $backupPath.Substring(4).Split(':')
                
                if ($refParts.Count -ge 3) {
                    $refBackupPath = $refParts[0]
                    $refFolderName = $refParts[1]
                    $refRelativePath = $refParts[2..$refParts.Count] -join ':'
                    
                    $refFilePath = Join-Path -Path (Join-Path -Path $refBackupPath -ChildPath $refFolderName) -ChildPath $refRelativePath
                    
                    if ($TestMode) {
                        $LogFunction.Invoke("  [TEST] Would restore (reference): $relativePath")
                    }
                    else {
                        try {
                            if (Test-Path -Path $refFilePath -PathType Leaf) {
                                Copy-Item -Path $refFilePath -Destination $destFilePath -Force
                                $LogFunction.Invoke("  Restored (reference): $relativePath")
                            }
                            else {
                                $LogFunction.Invoke("  -> ERROR: Referenced file not found: $refFilePath")
                            }
                        }
                        catch {
                            $LogFunction.Invoke("  -> ERROR: Failed to restore referenced file $relativePath: $_")
                        }
                    }
                }
                else {
                    $LogFunction.Invoke("  -> ERROR: Invalid reference format for $relativePath")
                }
            }
            else {
                $LogFunction.Invoke("  -> ERROR: Unknown backup path format for $relativePath: $backupPath")
            }
        }
        
        $successItems += "$sourceFolderName -> $targetPath"
        $LogFunction.Invoke("  Completed processing $fileCount files for $sourceFolderName.")
    }
    
    # Set up log files
    $logBase = Split-Path -Path $BackupPath -Parent
    $backupName = Split-Path -Path $BackupPath -Leaf
    $timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
    $restoreDetailsLogPath = Join-Path -Path $logBase -ChildPath "RestoreDetails_${backupName}_$timestamp.log"
    $skippedRestoreLogPath = Join-Path -Path $logBase -ChildPath "SkippedRestoreItems_${backupName}_$timestamp.log"
    $testModeLogPath = Join-Path -Path $logBase -ChildPath "TestRestoreSimulation_${backupName}_$timestamp.log"
    
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
                "--- TEST MODE RESTORE SIMULATION (INCREMENTAL) ---",
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
    $LogFunction.Invoke("Incremental restore operation completed in $elapsedFormatted")
    $LogFunction.Invoke("Items successfully processed: $($successItems.Count)")
    $LogFunction.Invoke("Items skipped: $($skippedItems.Count)")
    
    # Notify completion
    $CompleteFunction.Invoke(-not $operationFailed, $errors)
    
    return -not $operationFailed
}

# Export module functions
Export-ModuleMember -Function Invoke-IncrementalBackup, Restore-IncrementalBackup