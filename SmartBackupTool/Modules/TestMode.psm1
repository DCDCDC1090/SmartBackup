# TestMode.psm1
function Enable-TestMode {
    $script:config.TestModeEnabled = $true
    $script:config.Save()
    
    # Update UI indicators
    Update-TestModeUI
    
    # Log test mode activation
    Write-TestLog "TEST MODE ACTIVATED - All operations will be simulated"
}

function Disable-TestMode {
    $script:config.TestModeEnabled = $false
    $script:config.Save()
    
    # Update UI indicators
    Update-TestModeUI
    
    # Log test mode deactivation
    Write-TestLog "TEST MODE DEACTIVATED - Operations will execute normally"
}

function Write-TestLog {
    param (
        [string]$Message,
        [string]$Category = "General",
        [string]$Operation = "None"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = [PSCustomObject]@{
        Timestamp = $timestamp
        Category = $Category
        Operation = $Operation
        Message = $Message
    }
    
    # Add to in-memory log collection
    $script:testLogEntries += $logEntry
    
    # Write to log file
    $logPath = Join-Path -Path $script:config.LogsPath -ChildPath "TestMode_$($script:testSessionId).log"
    "$timestamp [$Category][$Operation] $Message" | Add-Content -Path $logPath -Encoding UTF8
    
    # If log box exists, update it
    if ($script:testLogBox) {
        $script:testLogBox.AppendText("$timestamp [$Category][$Operation] $Message`r`n")
        $script:testLogBox.ScrollToCaret()
    }
}

function Simulate-FileOperation {
    param (
        [string]$OperationType,
        [string]$SourcePath,
        [string]$DestinationPath,
        [long]$FileSize = 0,
        [bool]$IsDirectory = $false
    )
    
    # Simulate operation timing based on file size
    $estimatedTime = if ($IsDirectory) {
        # Directory operations take longer
        [TimeSpan]::FromMilliseconds(500) 
    } else {
        # File operations depend on size (very simple estimation)
        [TimeSpan]::FromMilliseconds([Math]::Max(10, $FileSize / 1MB * 100))
    }
    
    $pathType = if ($IsDirectory) { "Directory" } else { "File" }
    
    Write-TestLog "Simulating $OperationType operation for $pathType" -Category "FileOperation" -Operation $OperationType
    Write-TestLog "  Source: $SourcePath" -Category "FileOperation" -Operation $OperationType
    
    if ($DestinationPath) {
        Write-TestLog "  Destination: $DestinationPath" -Category "FileOperation" -Operation $OperationType
    }
    
    if ($FileSize -gt 0) {
        $sizeFormatted = Format-FileSize $FileSize
        Write-TestLog "  Size: $sizeFormatted" -Category "FileOperation" -Operation $OperationType
    }
    
    Write-TestLog "  Estimated time: $($estimatedTime.TotalSeconds) seconds" -Category "FileOperation" -Operation $OperationType
    
    # Return simulated result
    return @{
        Success = $true
        TimeTaken = $estimatedTime
        Message = "Operation simulated successfully"
    }
}

function Format-FileSize {
    param ([long]$Size)
    
    if ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size / 1GB) }
    elseif ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size / 1MB) }
    elseif ($Size -gt 1KB) { return "{0:N2} KB" -f ($Size / 1KB) }
    else { return "$Size bytes" }
}

function Show-TestReport {
    # Create a report form with all test log entries
    $reportForm = New-Object System.Windows.Forms.Form -Property @{
        Text = "Test Mode Report"
        Size = New-Object System.Drawing.Size(800, 600)
        StartPosition = "CenterParent"
    }
    
    $reportText = New-Object System.Windows.Forms.RichTextBox -Property @{
        Dock = [System.Windows.Forms.DockStyle]::Fill
        ReadOnly = $true
        Font = New-Object System.Drawing.Font("Consolas", 10)
    }
    
    # Generate summary statistics
    $operationCount = $script:testLogEntries | Group-Object -Property Operation | 
                      Where-Object { $_.Name -ne "None" } | 
                      Select-Object Name, Count
    
    $reportText.AppendText("TEST MODE SUMMARY REPORT`r`n")
    $reportText.AppendText("======================`r`n`r`n")
    $reportText.AppendText("Operations simulated:`r`n")
    
    foreach ($op in $operationCount) {
        $reportText.AppendText("- $($op.Name): $($op.Count) operations`r`n")
    }
    
    $reportText.AppendText("`r`nDETAILED LOG:`r`n")
    $reportText.AppendText("======================`r`n`r`n")
    
    foreach ($entry in $script:testLogEntries) {
        $reportText.AppendText("$($entry.Timestamp) [$($entry.Category)][$($entry.Operation)] $($entry.Message)`r`n")
    }
    
    $btnExport = New-Object System.Windows.Forms.Button -Property @{
        Text = "Export Report"
        Dock = [System.Windows.Forms.DockStyle]::Bottom
        Height = 30
    }
    
    $btnExport.Add_Click({
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog -Property @{
            Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
            Title = "Export Test Report"
            FileName = "TestReport_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
        }
        
        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $reportText.Text | Out-File -FilePath $saveDialog.FileName -Encoding UTF8
            [System.Windows.Forms.MessageBox]::Show(
                "Report exported to: $($saveDialog.FileName)", 
                "Export Successful",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    })
    
    $reportForm.Controls.Add($reportText)
    $reportForm.Controls.Add($btnExport)
    
    $reportForm.ShowDialog()
}

function Run-AutomatedTests {
    # Clear previous test logs
    $script:testLogEntries = @()
    $script:testSessionId = Get-Date -Format "yyyyMMdd_HHmmss"
    
    Write-TestLog "Starting automated test suite" -Category "AutoTest" -Operation "TestSuite"
    
    # Dictionary to track test results
    $testResults = @{}
    
    # Test 1: Configuration System
    $testResults["ConfigSystem"] = Test-ConfigurationSystem
    
    # Test 2: File Operations
    $testResults["FileOperations"] = Test-FileOperations
    
    # Test 3: Backup Process
    $testResults["BackupProcess"] = Test-BackupProcess
    
    # Test 4: Restore Process
    $testResults["RestoreProcess"] = Test-RestoreProcess
    
    # Test 5: Incremental Backup
    $testResults["IncrementalBackup"] = Test-IncrementalBackup
    
    # Test 6: Compression
    $testResults["Compression"] = Test-Compression
    
    # Generate summary report
    $passedTests = ($testResults.Values | Where-Object { $_ -eq $true }).Count
    $totalTests = $testResults.Count
    
    Write-TestLog "Automated Test Summary: $passedTests/$totalTests tests passed" -Category "AutoTest" -Operation "Summary"
    
    foreach ($test in $testResults.Keys) {
        $result = if ($testResults[$test]) { "PASSED" } else { "FAILED" }
        Write-TestLog "$test test: $result" -Category "AutoTest" -Operation "Summary"
    }
    
    # Show test report
    Show-TestReport
    
    return $testResults
}

# Individual test functions
function Test-ConfigurationSystem {
    Write-TestLog "Testing configuration system..." -Category "AutoTest" -Operation "ConfigTest"
    
    try {
        # Test 1: Create test profile
        $testProfileName = "AutoTestProfile_$([Guid]::NewGuid().ToString().Substring(0, 8))"
        $createResult = New-BackupProfile -ProfileName $testProfileName -Description "Automated Test Profile"
        
        if (-not $createResult) {
            throw "Failed to create test profile"
        }
        
        Write-TestLog "Created test profile: $testProfileName" -Category "AutoTest" -Operation "ConfigTest"
        
        # Test 2: Update profile settings
        $updateResult = Update-BackupProfile -ProfileName $testProfileName -Incremental $true -EnableCompression $true
        
        if (-not $updateResult) {
            throw "Failed to update test profile"
        }
        
        Write-TestLog "Updated test profile settings" -Category "AutoTest" -Operation "ConfigTest"
        
        # Test 3: Get profiles list
        $profiles = Get-BackupProfilesList
        
        if (-not ($profiles -contains $testProfileName)) {
            throw "Test profile not found in profiles list"
        }
        
        Write-TestLog "Test profile found in profiles list" -Category "AutoTest" -Operation "ConfigTest"
        
        # Clean up: Delete test profile
        $deleteResult = Remove-BackupProfile -ProfileName $testProfileName
        
        if (-not $deleteResult) {
            Write-TestLog "Warning: Failed to delete test profile" -Category "AutoTest" -Operation "ConfigTest"
        }
        
        return $true
    }
    catch {
        Write-TestLog "Configuration system test failed: $_" -Category "AutoTest" -Operation "ConfigTest"
        return $false
    }
}

function Test-FileOperations {
    Write-TestLog "Testing file operation simulation..." -Category "AutoTest" -Operation "FileTest"
    
    try {
        # Test directory creation
        $result = Simulate-FileOperation -OperationType "Create" -SourcePath "C:\TestDir" -IsDirectory $true
        
        if (-not $result.Success) {
            throw "Directory creation simulation failed"
        }
        
        # Test file copy
        $result = Simulate-FileOperation -OperationType "Copy" -SourcePath "C:\TestFile.txt" -DestinationPath "D:\Backup\TestFile.txt" -FileSize 1MB
        
        if (-not $result.Success) {
            throw "File copy simulation failed"
        }
        
        Write-TestLog "File operations test passed" -Category "AutoTest" -Operation "FileTest"
        return $true
    }
    catch {
        Write-TestLog "File operations test failed: $_" -Category "AutoTest" -Operation "FileTest"
        return $false
    }
}

# Add similar test functions for other components

Export-ModuleMember -Function Enable-TestMode, 
                            Disable-TestMode,
                            Write-TestLog,
                            Simulate-FileOperation,
                            Show-TestReport,
                            Run-AutomatedTests