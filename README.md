# SmartBackup
/C Drive Backup Personal Use


# SmartBackup

## Overview
SmartBackup is a PowerShell-based utility designed to backup C Drive content for personal use. This application allows you to create automated backups of important files and folders from your C Drive to ensure data safety.

## Project Structure
- **SmartBackup.ps1**: Main script - entry point for the application
- **Backup-Handler.ps1**: Contains core backup functionality
- **Config-Manager.ps1**: Manages configuration settings
- **File-Scanner.ps1**: Handles file scanning and selection
- **UI-Components/**: Interface elements and display functions
- **Helpers/**: Utility and helper functions

## Setup Instructions
1. Ensure PowerShell 5.1+ is installed on your system
2. Set execution policy to allow scripts (as Administrator):
   ```
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned
   ```
3. Configure backup settings in `config.json`
4. Run the application using one of the following methods:
   - Double-click `Run-SmartBackup.bat` in the application folder
   - From PowerShell: `.\SmartBackup.ps1`

## Terminal Closing Issue Fix

### Solution 1: Run from Existing PowerShell
Instead of double-clicking the script, open PowerShell and run:
```
cd path\to\SmartBackup
.\SmartBackup.ps1
```

### Solution 2: Add Error Trapping
Add this code to your SmartBackup.ps1 file:

```powershell
try {
    # Your existing PowerShell code here
    
    # Example:
    # Import-Module .\Backup-Handler.ps1
    # Start-Backup
}
catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
    Write-Host "Script failed at line: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    Write-Host "Stack Trace: $($_.ScriptStackTrace)" -ForegroundColor Red
}
finally {
    Write-Host "Press any key to exit..."
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
```

### Solution 3: Create a Batch File Launcher
Create a file named `Run-SmartBackup.bat` in your project folder:

```batch
@echo off
echo Running SmartBackup...
powershell -NoProfile -ExecutionPolicy Bypass -File "SmartBackup.ps1"
echo.
echo Execution finished. Check for errors above.
pause
```

## Troubleshooting Common Issues
- **Terminal Closes Immediately**: Use one of the solutions above to keep the terminal window open
- **Execution Policy Errors**: Run `Set-ExecutionPolicy RemoteSigned` as Administrator
- **Permission Issues**: Run PowerShell as Administrator when accessing protected directories
- **Configuration Issues**: Verify config.json has the correct format and paths

## Dependencies
- PowerShell 5.1+
- No additional modules required

## Contact/Notes
- GitHub Repository: https://github.com/DCDCDC1090/SmartBackup
- For issues or contributions, please create a GitHub issue


# Instructions for Next Claude Chat

Copy and paste the following text to continue your work with Claude on the PowerShell-based SmartBackup project:

```
I'm continuing work on my SmartBackup project that backs up files from C Drive. Our previous conversation focused on creating a PowerShell-based solution with proper error handling to address terminal closing issues.

GitHub repo: https://github.com/DCDCDC1090/SmartBackup

In our last session, you provided:
1. A comprehensive SmartBackup.ps1 script
2. config.json configuration file
3. Run-SmartBackup.bat launcher
4. Documentation and project structure

I've implemented these solutions but need help with the following:

1. I want to add compression functionality to create ZIP archives of backups
2. I'd like to implement a cleanup feature that removes backups older than X days
3. I need help creating a scheduled task to run the backup automatically

Please help me enhance the PowerShell script with these additional features.

Important files to focus on:
- SmartBackup.ps1 - The main script to enhance
- config.json - Configuration that may need new parameters
```

## Key Details About Your Project

If Claude asks for more information about your project, you can share:

1. SmartBackup is a PowerShell-based utility for backing up important files from C Drive
2. The main issue was the terminal window closing before error messages could be seen
3. You've implemented the error handling, logging, and batch launcher solutions
4. Your goal now is to add more advanced features to make the backup tool more useful
5. You prefer PowerShell solutions as they integrate well with Windows

## Terminal Issue Resolution Confirmation

If Claude asks about the terminal closing issue:

1. The implemented solution with try/catch/finally blocks and Read-Host pause is working
2. The batch file launcher successfully keeps the window open after script completion
3. The logging system now captures all errors and operations for later review

## Feature Enhancement Priorities

When discussing new features with Claude, your priorities are:

1. File compression to reduce backup size
2. Automatic cleanup of old backups to manage disk space
3. Scheduled execution using Windows Task Scheduler
4. Potential email notifications for backup status


# SmartBackup Project Map

## Files and Their Purpose

| Filename | Type | Purpose | Dependencies |
|----------|------|---------|--------------|
| SmartBackup.ps1 | PowerShell | Main entry point with backup functionality | config.json, Modules/ |
| Run-SmartBackup.bat | Batch | Launcher that keeps terminal open | SmartBackup.ps1 |
| config.json | JSON | Application configuration | None |

## Directory Structure
```
SmartBackup/
├── SmartBackup.ps1          # Main script
├── Run-SmartBackup.bat      # Launcher
├── config.json              # Configuration
├── Modules/                 # PowerShell modules
│   ├── BackupFunctions.psm1 # Core backup functionality
│   ├── ConfigManager.psm1   # Configuration management
│   ├── FileScanner.psm1     # File scanning and filtering
│   └── LogManager.psm1      # Logging utilities
├── Scripts/                 # Additional scripts
│   ├── Cleanup-OldBackups.ps1  # Maintenance script
│   └── Schedule-Backup.ps1     # Task scheduler helper
└── Logs/                    # Generated log files
    └── SmartBackup_*.log    # Timestamped logs
```

## Workflow Diagram
```
User → Run-SmartBackup.bat → SmartBackup.ps1 → [Load Modules] → Read config.json → Perform backup → Create logs
```

## Module Components

### Modules/BackupFunctions.psm1
- **Start-SmartBackup**: Main backup function
- **New-BackupArchive**: Creates compressed archives
- **Copy-BackupItems**: Copies files with filtering

### Modules/ConfigManager.psm1
- **Get-BackupConfig**: Loads and validates configuration
- **Test-ConfigurationPaths**: Validates paths exist
- **Save-ConfigSettings**: Updates configuration file

### Modules/FileScanner.psm1
- **Get-BackupCandidates**: Identifies files for backup
- **Test-ExclusionPattern**: Applies exclusion rules
- **Measure-BackupSize**: Calculates total backup size

### Modules/LogManager.psm1
- **Write-BackupLog**: Handles logging to console and file
- **Initialize-LogFile**: Creates log file with headers
- **Clear-OldLogs**: Removes outdated log files

## Terminal Closing Issue

### Problem
The PowerShell window closes immediately after execution, preventing users from seeing error messages.

### Solutions
1. **Integrated Error Handling**: Added try/catch/finally blocks with Read-Host pause
2. **Comprehensive Logging**: All operations logged to timestamped files
3. **Batch File Launcher**: Keeps the console window open

## How to Modify Configuration
Edit the config.json file to:
1. Change source paths (what to backup)
2. Change destination path (where to store backups)
3. Add/modify exclusion patterns
4. Update backup settings (compression, retention)

## Next Steps for Development
1. Add backup compression functionality
2. Implement automatic cleanup of old backups
3. Add scheduled task creation
4. Create a restore function
5. Add email notifications for backup status
