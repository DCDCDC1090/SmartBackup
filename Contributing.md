# SmartBackup Development Guide

This document provides instructions for contributing to and maintaining the SmartBackup project.

## Repository Structure

```
SmartBackup/
├── SmartBackup.ps1        # Main script file
├── config.json            # Configuration file
├── Logs/                  # Directory for log files
├── README.md              # User documentation
└── CONTRIBUTING.md        # This file
```

## Development Guidelines

### Important Notes

1. **Config File Location**: The `config.json` file must always be in the root directory alongside `SmartBackup.ps1`. The script looks for this file in the working directory, not in a subdirectory.

2. **Error Handling**: Ensure all functions have proper error handling and log errors appropriately.

3. **Logging**: Use the `Write-Log` function for all console output to ensure consistent formatting and appropriate logging.

### Code Style

- Use camelCase for function parameters and variables
- Use PascalCase for function names
- Include comments for complex code sections
- Maintain the current error handling structure

### Testing Changes

Before committing changes:

1. Test the script with various parameters: 
   ```powershell
   .\SmartBackup.ps1
   .\SmartBackup.ps1 -Force
   .\SmartBackup.ps1 -LogLevel "Debug"
   ```

2. Validate error handling by testing error scenarios:
   - Missing config file
   - Invalid paths
   - Insufficient permissions

3. Check log files to ensure they contain appropriate information

## Common Issues and Solutions

### "Configuration file not found" Error

This error occurs when:
- The config.json file is missing
- The config.json file is in a subdirectory instead of the root
- The script is run from a different directory

**Solution**: Ensure config.json is in the same directory as SmartBackup.ps1, or use the `-Force` parameter to create it automatically.

### PowerShell Execution Policy

If the script won't run due to execution policy restrictions:

**Solution**: Run PowerShell as Administrator and use:
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
```

### Permission Issues

If the script fails to access files or directories:

**Solution**: Ensure the script is run with Administrator privileges, especially when backing up system files.

## Updating Documentation

When making changes to the script:

1. Update the README.md file to reflect any new features or changes
2. Document any new configuration options
3. Update this CONTRIBUTING.md file if development practices change

## Version Control Practices

- Use semantic versioning (MAJOR.MINOR.PATCH)
- Add comments to commits explaining the purpose of changes
- Test all changes before pushing to the repository
