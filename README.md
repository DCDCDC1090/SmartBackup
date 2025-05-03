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
