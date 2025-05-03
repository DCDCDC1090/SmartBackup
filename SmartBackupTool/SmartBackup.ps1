<#
.SYNOPSIS
    SmartBackup - A PowerShell script for automated file backups
.DESCRIPTION
    This script performs automated backups of specified directories
    with comprehensive logging and error handling.
.NOTES
    Version:        1.0
    Author:         DCDCDC1090
    Creation Date:  2025-05-01
    Repository:     https://github.com/DCDCDC1090/SmartBackup
#>

#-----------------------------------------------------------[Parameters]------------------------------------------------------------
param (
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = ".\config.json",
    
    [Parameter(Mandatory = $false)]
    [switch]$Force,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet("Info", "Warning", "Error", "Debug")]
    [string]$LogLevel = "Info"
)

#-----------------------------------------------------------[Functions]------------------------------------------------------------

# Initialize global variables first
$Script:StartTime = Get-Date
$Script:LogFile = $null
$Script:LogPath = ".\Logs"  # Default log path before config is loaded

function Write-Log {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "DEBUG")]
        [string]$Level = "INFO"
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    # Write to console
    switch ($Level) {
        "INFO" { Write-Host $logMessage -ForegroundColor White }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "DEBUG" { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    # Only write to log file if LogPath and LogFile are defined
    if ($null -ne $Script:LogPath -and $Script:LogPath -ne "") {
        # Ensure log directory exists
        if (-not (Test-Path -Path $Script:LogPath)) {
            try {
                New-Item -Path $Script:LogPath -ItemType Directory -Force | Out-Null
                Write-Host "Created log directory: $Script:LogPath"
            }
            catch {
                Write-Host "ERROR: Unable to create log directory: $_" -ForegroundColor Red
            }
        }
        
        # Only write to log file if LogFile is defined
        if ($null -ne $Script:LogFile -and $Script:LogFile -ne "") {
            try {
                Add-Content -Path $Script:LogFile -Value $logMessage
            }
            catch {
                Write-Host "ERROR: Unable to write to log file: $_" -ForegroundColor Red
            }
        }
    }
}

function Get-BackupConfig {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ConfigPath
    )
    
    Write-Host "Loading configuration from: $ConfigPath"
    
    if (-not (Test-Path -Path $ConfigPath)) {
        Write-Host "Configuration file not found: $ConfigPath" -ForegroundColor Red
        
        # Create default config if it doesn't exist
        if ($Force) {
            try {
                $defaultConfig = @{
                    BackupSettings = @{
                        SourcePath = "C:\"
                        DestinationPath = "D:\Backups"
                        ExcludeFolders = @("Windows", "Program Files", "Program Files (x86)", "ProgramData", "Temp")
                        BackupFrequency = "Daily"
                        RetentionDays = 30
                        CompressionLevel = "Optimal"
                    }
                    LogSettings = @{
                        LogPath = ".\Logs"
                        LogLevel = "Info"
                        MaxLogFiles = 10
                        MaxLogSize = 5
                    }
                    EmailNotification = @{
                        Enabled = $false
                        SmtpServer = ""
                        Port = 587
                        UseSsl = $true
                        Username = ""
                        Password = ""
                        FromAddress = ""
                        ToAddress = ""
                        Subject = "SmartBackup Notification"
                    }
                }
                
                $defaultConfig | ConvertTo-Json -Depth 4 | Out-File -FilePath $ConfigPath -Encoding utf8
                Write-Host "Created default configuration file: $ConfigPath" -ForegroundColor Green
            }
            catch {
                $errorMessage = "Failed to create default configuration file: $_"
                Write-Host $errorMessage -ForegroundColor Red
                throw "Unable to load configuration: $errorMessage"
            }
        }
        else {
            throw "Unable to load configuration: Configuration file not found: $ConfigPath"
        }
    }
    
    try {
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
        Write-Host "Configuration loaded successfully" -ForegroundColor Green
        return $config
    }
    catch {
        $errorMessage = "Failed to parse configuration file: $_"
        Write-Host $errorMessage -ForegroundColor Red
        throw "Unable to load configuration: $errorMessage"
    }
}

function Start-Backup {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    $backupSettings = $Config.BackupSettings
    $sourcePath = $backupSettings.SourcePath
    $destinationPath = $backupSettings.DestinationPath
    $excludeFolders = $backupSettings.ExcludeFolders
    
    # Validate source and destination
    if (-not (Test-Path -Path $sourcePath)) {
        Write-Log "Source path does not exist: $sourcePath" -Level "ERROR"
        return $false
    }
    
    # Create destination if it doesn't exist
    if (-not (Test-Path -Path $destinationPath)) {
        try {
            New-Item -Path $destinationPath -ItemType Directory -Force | Out-Null
            Write-Log "Created destination directory: $destinationPath" -Level "INFO"
        }
        catch {
            Write-Log "Failed to create destination directory: $_" -Level "ERROR"
            return $false
        }
    }
    
    # Create timestamp folder for this backup
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $backupFolder = Join-Path -Path $destinationPath -ChildPath $timestamp
    
    try {
        New-Item -Path $backupFolder -ItemType Directory -Force | Out-Null
        Write-Log "Created backup folder: $backupFolder" -Level "INFO"
    }
    catch {
        Write-Log "Failed to create backup folder: $_" -Level "ERROR"
        return $false
    }
    
    # Build robocopy exclude parameters
    $excludeParams = @()
    foreach ($folder in $excludeFolders) {
        $excludeParams += "/XD"
        $excludeParams += """$folder"""
    }
    
    # Start backup
    Write-Log "Starting backup from $sourcePath to $backupFolder" -Level "INFO"
    
    try {
        # Using robocopy for reliable file copying
        $robocopyArgs = @(
            """$sourcePath"""
            """$backupFolder"""
            "/E"             # Copy subdirectories, including empty ones
            "/Z"             # Copy files in restartable mode
            "/R:3"           # Number of retries
            "/W:5"           # Wait time between retries
            "/MT:8"          # Multi-threaded copying with 8 threads
            "/NFL"           # No file list - don't log file names
            "/NDL"           # No directory list - don't log directory names
            "/NP"            # No progress - don't display percentage copied
            "/LOG+:$Script:LogPath\Robocopy_$timestamp.log"
        ) + $excludeParams
        
        Write-Log "Executing robocopy with arguments: $($robocopyArgs -join ' ')" -Level "DEBUG"
        
        $process = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -PassThru -Wait
        
        # Interpret robocopy exit code
        # Codes 0-7 are successful, 8+ indicate at least one failure
        if ($process.ExitCode -lt 8) {
            Write-Log "Backup completed successfully with exit code: $($process.ExitCode)" -Level "INFO"
            return $true
        }
        else {
            Write-Log "Backup completed with some errors. Exit code: $($process.ExitCode)" -Level "WARNING"
            return $false
        }
    }
    catch {
        Write-Log "Backup failed: $_" -Level "ERROR"
        return $false
    }
}

function Remove-OldBackups {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    $backupSettings = $Config.BackupSettings
    $destinationPath = $backupSettings.DestinationPath
    $retentionDays = $backupSettings.RetentionDays
    
    if (-not (Test-Path -Path $destinationPath)) {
        Write-Log "Destination path does not exist: $destinationPath" -Level "WARNING"
        return
    }
    
    $cutoffDate = (Get-Date).AddDays(-$retentionDays)
    Write-Log "Removing backups older than $cutoffDate" -Level "INFO"
    
    try {
        $oldFolders = Get-ChildItem -Path $destinationPath -Directory |
                      Where-Object { $_.CreationTime -lt $cutoffDate }
        
        foreach ($folder in $oldFolders) {
            Write-Log "Removing old backup: $($folder.FullName)" -Level "INFO"
            Remove-Item -Path $folder.FullName -Recurse -Force
        }
        
        Write-Log "Removed $($oldFolders.Count) old backup(s)" -Level "INFO"
    }
    catch {
        Write-Log "Failed to remove old backups: $_" -Level "ERROR"
    }
}

#-----------------------------------------------------------[Execution]------------------------------------------------------------

try {
    # Display initial message
    Write-Host "Starting SmartBackup..." -ForegroundColor Green
    
    # Load configuration
    $config = Get-BackupConfig -ConfigPath $ConfigPath
    
    # Initialize logging from config
    $Script:LogPath = $config.LogSettings.LogPath
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Script:LogFile = Join-Path -Path $Script:LogPath -ChildPath "SmartBackup_$timestamp.log"
    
    # Create log directory if it doesn't exist
    if (-not (Test-Path -Path $Script:LogPath)) {
        New-Item -Path $Script:LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Start log
    Write-Log "Starting SmartBackup..." -Level "INFO"
    
    # Perform backup
    $backupResult = Start-Backup -Config $config
    
    # Clean up old backups
    if ($backupResult) {
        Remove-OldBackups -Config $config
    }
    
    # Calculate execution time
    $executionTime = (Get-Date) - $Script:StartTime
    $executionTimeString = "{0:hh\:mm\:ss}" -f $executionTime
    
    # Log summary
    if ($backupResult) {
        Write-Log "Backup completed successfully in $executionTimeString" -Level "INFO"
    }
    else {
        Write-Log "Backup completed with errors in $executionTimeString" -Level "WARNING"
    }
}
catch {
    # Handle any unhandled exceptions
    $errorMessage = "Error in script $($MyInvocation.MyCommand.Path) at line $($_.InvocationInfo.ScriptLineNumber)"
    Write-Host "$errorMessage" -ForegroundColor Red
    Write-Host "Command:         $($_.InvocationInfo.Line)" -ForegroundColor Red
    Write-Host "Error Message: $_" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
    
    # Log error summary if logging is already initialized
    if ($null -ne $Script:LogFile -and $Script:LogFile -ne "") {
        Write-Log $errorMessage -Level "ERROR"
        Write-Log "Command:         $($_.InvocationInfo.Line)" -Level "ERROR"
        Write-Log "Error Message: $_" -Level "ERROR"
        Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level "ERROR"
    }
    
    # Create an error summary for display
    Write-Host "`n===== ERROR SUMMARY =====" -ForegroundColor Red
    Write-Host "An error occurred during backup execution" -ForegroundColor Red
    
    if ($null -ne $Script:LogFile -and $Script:LogFile -ne "") {
        Write-Host "See log file for details: $Script:LogFile" -ForegroundColor Red
    }
    
    Write-Host "=======================" -ForegroundColor Red
}
finally {
    # Final cleanup and exit
    Write-Host "Press Enter to exit..." -ForegroundColor Yellow
    Read-Host
}
