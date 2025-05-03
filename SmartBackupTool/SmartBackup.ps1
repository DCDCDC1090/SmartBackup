#requires -Version 5.1
<#
.SYNOPSIS
    SmartBackup - C Drive Backup Tool
.DESCRIPTION
    A PowerShell script for backing up important files from C Drive
.NOTES
    File Name      : SmartBackup.ps1
    Prerequisite   : PowerShell 5.1 or later
.EXAMPLE
    .\SmartBackup.ps1
#>

# Setup logging
$LogFolder = ".\Logs"
$LogFile = Join-Path -Path $LogFolder -ChildPath "SmartBackup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

# Create log directory if it doesn't exist
if (-not (Test-Path -Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory | Out-Null
}

# Function to write to log file
function Write-Log {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Message,
        
        [Parameter()]
        [ValidateSet('INFO', 'WARNING', 'ERROR')]
        [string]$Level = 'INFO'
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    # Write to console with color coding
    switch ($Level) {
        'INFO'    { Write-Host $LogMessage -ForegroundColor Cyan }
        'WARNING' { Write-Host $LogMessage -ForegroundColor Yellow }
        'ERROR'   { Write-Host $LogMessage -ForegroundColor Red }
    }
    
    # Write to log file
    Add-Content -Path $LogFile -Value $LogMessage
}

# Function to load configuration
function Get-BackupConfig {
    param (
        [string]$ConfigPath = ".\config.json"
    )
    
    try {
        if (Test-Path -Path $ConfigPath) {
            $ConfigJson = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
            Write-Log "Configuration loaded successfully"
            return $ConfigJson
        } else {
            Write-Log "Configuration file not found: $ConfigPath" -Level 'ERROR'
            throw "Configuration file not found: $ConfigPath"
        }
    } catch {
        Write-Log "Error loading configuration: $_" -Level 'ERROR'
        throw "Unable to load configuration: $_"
    }
}

# Function to perform backup
function Start-SmartBackup {
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )
    
    Write-Log "Starting backup process..."
    
    # Validate source directories
    foreach ($Source in $Config.SourcePaths) {
        if (-not (Test-Path -Path $Source)) {
            Write-Log "Source path not found: $Source" -Level 'WARNING'
        }
    }
    
    # Validate destination
    if (-not (Test-Path -Path $Config.DestinationPath)) {
        Write-Log "Creating destination directory: $($Config.DestinationPath)"
        try {
            New-Item -Path $Config.DestinationPath -ItemType Directory -Force | Out-Null
        } catch {
            Write-Log "Failed to create destination directory: $_" -Level 'ERROR'
            throw "Failed to create destination directory: $_"
        }
    }
    
    # Create backup folder with timestamp
    $BackupFolder = Join-Path -Path $Config.DestinationPath -ChildPath "Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    New-Item -Path $BackupFolder -ItemType Directory | Out-Null
    Write-Log "Created backup folder: $BackupFolder"
    
    # Perform backup for each source
    foreach ($Source in $Config.SourcePaths) {
        if (Test-Path -Path $Source) {
            Write-Log "Backing up: $Source"
            
            # Get relative path for creating folder structure
            $DestSubPath = Split-Path -Path $Source -Leaf
            $DestPath = Join-Path -Path $BackupFolder -ChildPath $DestSubPath
            
            try {
                # Copy with progress display
                $CopyParams = @{
                    Path = $Source
                    Destination = $DestPath
                    Recurse = $true
                    Force = $true
                }
                
                if ($Config.ExcludePatterns -and $Config.ExcludePatterns.Count -gt 0) {
                    Write-Log "Applying exclusion patterns"
                    $Items = Get-ChildItem -Path $Source -Recurse | 
                             Where-Object { 
                                 $Item = $_
                                 -not ($Config.ExcludePatterns | Where-Object { $Item.FullName -like $_ })
                             }
                    
                    foreach ($Item in $Items) {
                        $RelativePath = $Item.FullName.Substring($Source.Length)
                        $TargetPath = Join-Path -Path $DestPath -ChildPath $RelativePath
                        
                        if ($Item.PSIsContainer) {
                            if (-not (Test-Path -Path $TargetPath)) {
                                New-Item -Path $TargetPath -ItemType Directory -Force | Out-Null
                            }
                        } else {
                            $TargetDir = Split-Path -Path $TargetPath -Parent
                            if (-not (Test-Path -Path $TargetDir)) {
                                New-Item -Path $TargetDir -ItemType Directory -Force | Out-Null
                            }
                            Copy-Item -Path $Item.FullName -Destination $TargetPath -Force
                        }
                    }
                } else {
                    # Simple copy if no exclusions
                    Copy-Item @CopyParams
                }
                
                Write-Log "Successfully backed up: $Source"
            } catch {
                Write-Log "Error backing up $Source`: $_" -Level 'ERROR'
            }
        }
    }
    
    Write-Log "Backup completed to: $BackupFolder"
    return $BackupFolder
}

# Main execution block with error handling
try {
    Write-Log "Starting SmartBackup..."
    
    # Load configuration
    $Config = Get-BackupConfig -ConfigPath ".\config.json"
    
    # Perform backup
    $BackupLocation = Start-SmartBackup -Config $Config
    
    Write-Log "Backup completed successfully to $BackupLocation"
}
catch {
    $ErrorMessage = $_.Exception.Message
    $LineNumber = $_.InvocationInfo.ScriptLineNumber
    $Command = $_.InvocationInfo.Line
    $ScriptName = $_.InvocationInfo.ScriptName
    
    Write-Log "Error in script $ScriptName at line $LineNumber" -Level 'ERROR'
    Write-Log "Command: $Command" -Level 'ERROR'
    Write-Log "Error Message: $ErrorMessage" -Level 'ERROR'
    Write-Log "Stack Trace: $($_.ScriptStackTrace)" -Level 'ERROR'
    
    # Display error summary to console
    Write-Host "`n===== ERROR SUMMARY =====" -ForegroundColor Red
    Write-Host "An error occurred during backup execution" -ForegroundColor Red
    Write-Host "See log file for details: $LogFile" -ForegroundColor Yellow
    Write-Host "=======================`n" -ForegroundColor Red
}
finally {
    # This ensures the terminal stays open
    Write-Host "`nPress Enter to exit..." -ForegroundColor Green
    Read-Host
}
