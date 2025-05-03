# SmartBackup

A PowerShell script for automated C: drive backup for personal use.

## Project Overview

SmartBackup is a robust PowerShell-based backup solution designed for personal use. It creates incremental backups of your C: drive while allowing you to customize which folders to include or exclude.

### Project Map

```
SmartBackup/
├── SmartBackup.ps1        # Main script file
├── config.json            # Configuration file (must be in root directory)
├── Logs/                  # Directory for log files (created automatically)
│   └── SmartBackup_*.log  # Timestamped log files
└── README.md              # Documentation
```

## Quick Setup

1. **Download the project** from GitHub
2. **Place config.json** in the same directory as SmartBackup.ps1
3. **Run the script**: `.\SmartBackup.ps1`
4. **Check logs** in the Logs directory to verify backup success

## Features

- Automated backup of specified directories
- Configurable source and destination paths
- Folder exclusion to skip unnecessary files
- Retention policy for automatic cleanup of old backups
- Comprehensive logging with different verbosity levels
- Email notification support (optional)

## Detailed Setup Instructions

### 1. Download and Install

1. Download the project files from GitHub
2. Extract to a location of your choice (e.g., D:\SmartBackupTool)
3. Make sure SmartBackup.ps1 and config.json are in the same directory

### 2. Configure Settings

Edit the config.json file to customize your backup settings:

```json
{
  "BackupSettings": {
    "SourcePath": "C:\\",                                  // Source directory to backup
    "DestinationPath": "D:\\Backups",                      // Destination for backups
    "ExcludeFolders": [                                    // Folders to exclude
      "Windows",
      "Program Files",
      "Program Files (x86)",
      "ProgramData",
      "Temp"
    ],
    "BackupFrequency": "Daily",                            // Backup frequency
    "RetentionDays": 30,                                   // Number of days to keep backups
    "CompressionLevel": "Optimal"                          // Compression level
  },
  "LogSettings": {
    "LogPath": ".\\Logs",                                  // Path for log files
    "LogLevel": "Info",                                    // Log verbosity (Info, Warning, Error, Debug)
    "MaxLogFiles": 10,                                     // Maximum number of log files to keep
    "MaxLogSize": 5                                        // Maximum log file size in MB
  },
  "EmailNotification": {
    "Enabled": false,                                      // Enable email notifications
    "SmtpServer": "",                                      // SMTP server address
    "Port": 587,                                           // SMTP port
    "UseSsl": true,                                        // Use SSL for SMTP
    "Username": "",                                        // SMTP username
    "Password": "",                                        // SMTP password
    "FromAddress": "",                                     // Sender email address
    "ToAddress": "",                                       // Recipient email address
    "Subject": "SmartBackup Notification"                  // Email subject
  }
}
```

### 3. Run the Script

Run the script from PowerShell:

```powershell
.\SmartBackup.ps1
```

For first-time setup, you can use the `-Force` parameter to create a default config.json if it doesn't exist:

```powershell
.\SmartBackup.ps1 -Force
```

### 4. Schedule Automatic Backups

To schedule automated backups, use Windows Task Scheduler:

1. Open Task Scheduler
2. Create a new task
3. Set the action to start a program:
   - Program/script: `powershell.exe`
   - Arguments: `-ExecutionPolicy Bypass -File "D:\path\to\SmartBackup.ps1"`
4. Set the trigger to your desired schedule (daily, weekly, etc.)
5. Ensure the task runs with sufficient privileges

## Usage Options

```powershell
.\SmartBackup.ps1 -ConfigPath "C:\path\to\config.json" -Force -LogLevel "Debug"
```

Parameters:
- `-ConfigPath`: Path to the configuration file (default: .\config.json)
- `-Force`: Create a default configuration file if it doesn't exist
- `-LogLevel`: Set the logging level (Info, Warning, Error, Debug)

## Troubleshooting

If you encounter issues:

1. Check the log files for detailed error messages
2. Ensure the configuration file is correctly formatted JSON and in the same directory as the script
3. Verify that source and destination paths exist and are accessible
4. Run the script with `-LogLevel "Debug"` for more detailed logs
5. If you see "Configuration file not found" errors, make sure config.json is in the same directory as the script, not in a subdirectory
