# SmartBackup.ps1 - Main entry script for Smart Backup Tool
#
# Usage:
# .\SmartBackup.ps1 # Run with GUI
# .\SmartBackup.ps1 -AutoRun # Run scheduled backup without GUI
# .\SmartBackup.ps1 -ProfileName Work # Run with specific profile

param (
    [switch]$AutoRun,
    [string]$ProfileName = "Default"
)

# Script metadata
$script:Version = "2.0.0"
$script:ScriptPath = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$script:ModulesPath = Join-Path -Path $script:ScriptPath -ChildPath "Modules"
$script:ConfigPath = Join-Path -Path $script:ScriptPath -ChildPath "config"
$script:LogsPath = Join-Path -Path $script:ScriptPath -ChildPath "logs"
$script:testSessionId = Get-Date -Format "yyyyMMdd_HHmmss"

# Ensure directories exist
foreach ($path in @($script:ModulesPath, $script:ConfigPath, $script:LogsPath)) {
    if (-not (Test-Path -Path $path -PathType Container)) {
        New-Item -Path $path -ItemType Directory -Force | Out-Null
    }
}

# Bootstrap: Create default config if missing
$defaultConfigPath = Join-Path -Path $script:ConfigPath -ChildPath "config.json"
if (-not (Test-Path -Path $defaultConfigPath -PathType Leaf)) {
    @{
        DefaultBackupRoot = "D:\NEW_OS_BACKUP"
        TempBackupRoot = "D:\NEW_OS_BACKUP\_tempReview"
        DefaultProfileName = "Default"
        EnableReviewMode = $true
        EnableScreenshot = $true
        DisableFirefoxBackup = $false
        EnableTestRestore = $true
        TestModeEnabled = $false
        Profiles = @{
            Default = @{
                Description = "Default backup profile"
                Incremental = $false
                Compression = @{
                    Enabled = $false
                    Level = "Normal"
                }
            }
        }
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $defaultConfigPath -Encoding UTF8
}

# Import required .NET assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Import core required modules
$modulesToImport = @(
    "Config",
    "FileUtils"
)

foreach ($module in $modulesToImport) {
    $modulePath = Join-Path -Path $script:ModulesPath -ChildPath "$module.psm1"
    if (Test-Path -Path $modulePath -PathType Leaf) {
        Import-Module $modulePath -Force -ErrorAction Stop
    } else {
        Write-Warning "Core module not found: $modulePath"
        exit 1
    }
}

# Initialize error handling
Initialize-ErrorHandling -LogPath $script:LogsPath

# Initialize configuration
$config = Initialize-Configuration -ConfigPath $script:ConfigPath -ProfileName $ProfileName

# Apply DPI awareness for better UI scaling
Set-DPIAwareness

# Import GUI modules if not in AutoRun mode
if (-not $AutoRun) {
    # Import operation modules first (needed by GUI)
    $operationModules = @(
        "BackupOperations",
        "Compression",
        "IncrementalBackup",
        "Scheduler",
        "TestMode"
    )
    
    foreach ($module in $operationModules) {
        $modulePath = Join-Path -Path $script:ModulesPath -ChildPath "$module.psm1"
        if (Test-Path -Path $modulePath -PathType Leaf) {
            Import-Module $modulePath -Force -ErrorAction Stop
        } else {
            Write-Warning "Operation module not found: $modulePath"
            # Not exiting since these are optional for basic UI functionality
        }
    }
    
    # Import GUI modules
    $guiModules = @(
        "CoreGUI",
        "FolderListModule",
        "ActionModule",
        "ConfigModule",
        "ConfigModuleUI"
    )
    
    foreach ($module in $guiModules) {
        $modulePath = Join-Path -Path $script:ModulesPath -ChildPath "$module.psm1"
        if (Test-Path -Path $modulePath -PathType Leaf) {
            Import-Module $modulePath -Force -ErrorAction Stop
        } else {
            Write-Warning "GUI module not found: $modulePath"
            exit 1
        }
    }
    
    # Start the GUI
    Show-BackupGUI -Config $config
} else {
    # Import operation modules for AutoRun mode
    $operationModules = @(
        "BackupOperations",
        "Compression",
        "IncrementalBackup"
    )
    
    foreach ($module in $operationModules) {
        $modulePath = Join-Path -Path $script:ModulesPath -ChildPath "$module.psm1"
        if (Test-Path -Path $modulePath -PathType Leaf) {
            Import-Module $modulePath -Force -ErrorAction Stop
        } else {
            Write-Warning "Operation module not found: $modulePath"
            exit 1
        }
    }
    
    # Start automated backup
    Start-AutomatedBackup -Config $config
}