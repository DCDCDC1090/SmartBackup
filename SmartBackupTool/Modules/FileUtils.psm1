# FileUtils.psm1 - File operation utilities

function Initialize-ErrorHandling {
    [CmdletBinding()]
    param (
        [string]$LogPath
    )
    
    # Create log directory if it doesn't exist
    if (-not (Test-Path -Path $LogPath -PathType Container)) {
        New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
    }
    
    # Set global error log path
    $script:ErrorLogPath = Join-Path -Path $LogPath -ChildPath "errors.log"
    
    # Set up global error handler
    $global:ErrorActionPreference = "Continue"
    
    # Register error event handler
    $null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action {
        if ($global:Error.Count -gt 0) {
            $latestError = $global:Error[0]
            
            # Log error to file
            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $errorInfo = "[$timestamp] $($latestError.Exception.GetType().FullName): $($latestError.Exception.Message)"
            $errorInfo | Out-File -FilePath $script:ErrorLogPath -Append -Encoding UTF8
            
            # Additional details for critical errors
            if ($latestError.Exception -is [System.OutOfMemoryException] -or 
                $latestError.Exception -is [System.StackOverflowException]) {
                $errorDetails = "Stack Trace: $($latestError.ScriptStackTrace)"
                $errorDetails | Out-File -FilePath $script:ErrorLogPath -Append -Encoding UTF8
            }
        }
    }
}

function Get-KnownBackupFolders {
    [CmdletBinding()]
    param()
    
    # Use environment variables for user profile paths
    $userProfile = $env:USERPROFILE
    $localAppData = $env:LOCALAPPDATA
    $roamingAppData = $env:APPDATA
    $savedGamesPath = Join-Path $userProfile 'Saved Games'
    $localLowPath = Join-Path $env:LOCALAPPDATA '..\LocalLow' # More reliable way to get LocalLow
    
    $paths = @(
        (Join-Path $userProfile 'Documents'),
        (Join-Path $userProfile 'Desktop'),
        (Join-Path $userProfile 'Pictures'),
        (Join-Path $userProfile 'Music'),
        $roamingAppData,
        $localAppData,
        $savedGamesPath,
        $localLowPath
    )
    
    # Filter for existing paths
    $existingPaths = $paths | Where-Object { Test-Path $_ -PathType Container }
    
    return $existingPaths
}

function Get-FirefoxProfilePath {
    [CmdletBinding()]
    param()
    
    $roamingAppData = $env:APPDATA
    $firefoxRoamingPath = Join-Path $roamingAppData 'Mozilla\Firefox'
    $profilesPath = Join-Path $firefoxRoamingPath 'Profiles'
    
    if (Test-Path $profilesPath -PathType Container) {
        # Look for a profile directory (often ends with .default or .default-release)
        $profileDir = Get-ChildItem $profilesPath -Directory | 
                       Where-Object { $_.Name -like '*.default*' } | 
                       Select-Object -First 1
        if ($profileDir) { return $profileDir.FullName }
        
        # Fallback: just return the first profile found if no default named one exists
        $profileDir = Get-ChildItem $profilesPath -Directory | Select-Object -First 1
        if ($profileDir) { return $profileDir.FullName }
    }
    
    # Fallback: If Profiles folder doesn't exist but Mozilla\Firefox does, return that
    if (Test-Path $firefoxRoamingPath -PathType Container) {
        Write-Verbose "Firefox Profiles folder not found, returning base Firefox Roaming path."
        return $firefoxRoamingPath
    }
    
    return $null # Return null if no path found
}

function Analyze-ProgramDependencies {
    [CmdletBinding()]
    param()
    
    $programFiles = $env:ProgramFiles
    $programFilesX86 = ${env:ProgramFiles(x86)}
    $userProfile = $env:USERPROFILE
    $localAppData = $env:LOCALAPPDATA
    $roamingAppData = $env:APPDATA
    
    $dirs = @()
    # Define potential installation roots
    $searchRoots = @(
        $programFiles,
        $programFilesX86,
        "D:\Games",
        "D:\Apps",
        "C:\Games",
        "E:\Games",
        "F:\Games"
    )
    
    # Add roots only if they exist
    $validSearchRoots = $searchRoots | Where-Object { $_ -and (Test-Path $_ -PathType Container) }
    
    # Get top-level directories in valid roots
    foreach ($s in $validSearchRoots) {
        try {
            $dirs += Get-ChildItem $s -Directory -ErrorAction SilentlyContinue
        } catch {
            Write-Warning "Could not access '$s' during dependency scan: $($_.Exception.Message)"
        }
    }
    
    $related = @()
    foreach ($d in $dirs) {
        $n = $d.Name # Program name guess
        # Check corresponding AppData and Documents folders
        foreach ($p in @(
            (Join-Path $localAppData $n),
            (Join-Path $roamingAppData $n),
            (Join-Path $userProfile "Documents\$n"),
            (Join-Path $userProfile "AppData\LocalLow\$n")
        )) {
            if (Test-Path $p -PathType Container) {
                $related += $p
            }
        }
    }
    
    # Return unique, sorted list
    $related | Sort-Object -Unique
}

function Get-FileHash {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$FilePath,
        
        [ValidateSet("MD5", "SHA1", "SHA256", "SHA384", "SHA512")]
        [string]$Algorithm = "SHA256"
    )
    
    try {
        # Use built-in Get-FileHash cmdlet if running on PowerShell 4.0 or later
        if ($PSVersionTable.PSVersion.Major -ge 4) {
            $hash = Microsoft.PowerShell.Utility\Get-FileHash -Path $FilePath -Algorithm $Algorithm
            return $hash.Hash
        }
        else {
            # Fallback implementation for PowerShell 2.0/3.0
            $algorithmObj = [System.Security.Cryptography.HashAlgorithm]::Create($Algorithm)
            $fileStream = [System.IO.File]::OpenRead($FilePath)
            
            try {
                $hashBytes = $algorithmObj.ComputeHash($fileStream)
                $hashString = [BitConverter]::ToString($hashBytes) -replace '-', ''
                return $hashString
            }
            finally {
                $fileStream.Close()
                $fileStream.Dispose()
                $algorithmObj.Clear()
                $algorithmObj.Dispose()
            }
        }
    }
    catch {
        Write-Error "Failed to calculate file hash for '$FilePath': $_"
        return $null
    }
}

function Compare-FileTimes {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [string]$TargetPath
    )
    
    try {
        if (-not (Test-Path -Path $SourcePath -PathType Leaf)) {
            Write-Verbose "Source file not found: $SourcePath"
            return -1 # Source doesn't exist
        }
        
        if (-not (Test-Path -Path $TargetPath -PathType Leaf)) {
            Write-Verbose "Target file not found: $TargetPath"
            return 1 # Target doesn't exist, so source is newer
        }
        
        $sourceItem = Get-Item -Path $SourcePath
        $targetItem = Get-Item -Path $TargetPath
        
        # Compare last write times
        if ($sourceItem.LastWriteTime -gt $targetItem.LastWriteTime) {
            return 1 # Source is newer
        }
        elseif ($sourceItem.LastWriteTime -lt $targetItem.LastWriteTime) {
            return -1 # Target is newer
        }
        else {
            # Times are equal, check file size
            if ($sourceItem.Length -ne $targetItem.Length) {
                return 2 # Same time but different size
            }
            else {
                return 0 # Identical timestamp and size
            }
        }
    }
    catch {
        Write-Error "Error comparing file times: $_"
        return -2 # Error
    }
}

function Get-FileSystemItems {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path,
        
        [switch]$Recurse,
        
        [string[]]$ExcludePatterns
    )
    
    try {
        $params = @{
            Path = $Path
            ErrorAction = "Stop"
        }
        
        if ($Recurse) {
            $params.Recurse = $true
        }
        
        $results = @()
        
        if (Test-Path -Path $Path -PathType Container) {
            $items = Get-ChildItem @params
            
            # Apply exclusion patterns if specified
            if ($ExcludePatterns -and $ExcludePatterns.Count -gt 0) {
                $filteredItems = @()
                foreach ($item in $items) {
                    $exclude = $false
                    foreach ($pattern in $ExcludePatterns) {
                        if ($item.FullName -like $pattern) {
                            $exclude = $true
                            break
                        }
                    }
                    if (-not $exclude) {
                        $filteredItems += $item
                    }
                }
                $results = $filteredItems
            }
            else {
                $results = $items
            }
        }
        
        return $results
    }
    catch {
        Write-Error "Error getting file system items from '$Path': $_"
        return @()
    }
}

function Set-DPIAwareness {
    [CmdletBinding()]
    param()
    
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace Win32 {
    public static class DPIHelper {
        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();
    }
}
"@ -Language CSharp -ErrorAction Stop
        
        [Win32.DPIHelper]::SetProcessDPIAware() | Out-Null
        Write-Verbose "DPI awareness enabled for the process"
    }
    catch {
        Write-Warning "Failed to set DPI awareness: $($_.Exception.Message)"
    }
}

function Capture-DesktopScreenshot {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$OutputPath,
        
        [switch]$MinimizeWindows
    )
    
    try {
        # Ensure the target directory exists
        $targetDir = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -Path $targetDir -PathType Container)) {
            New-Item -Path $targetDir -ItemType Directory -Force | Out-Null
        }
        
        # Load required assemblies
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        
        $shellApp = $null
        $bmp = $null
        $g = $null
        
        try {
            if ($MinimizeWindows) {
                $shellApp = New-Object -ComObject Shell.Application
                $shellApp.MinimizeAll()
                Start-Sleep -Milliseconds 500
            }
            
            $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
            $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            
            # Copy screen content
            $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
            
            # Save to file
            $bmp.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
            Write-Verbose "Screenshot saved to: $OutputPath"
            
            return $true
        }
        finally {
            # Clean up resources
            if ($g) { $g.Dispose() }
            if ($bmp) { $bmp.Dispose() }
            if ($shellApp) {
                try {
                    $shellApp.UndoMinimizeAll()
                    [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shellApp) | Out-Null
                }
                catch {
                    Write-Warning "Error restoring windows: $($_.Exception.Message)"
                }
                $shellApp = $null
            }
        }
    }
    catch {
        Write-Error "Failed to capture screenshot: $_"
        return $false
    }
}

# Export functions
Export-ModuleMember -Function Initialize-ErrorHandling,
                              Get-KnownBackupFolders,
                              Get-FirefoxProfilePath,
                              Analyze-ProgramDependencies,
                              Get-FileHash,
                              Compare-FileTimes,
                              Get-FileSystemItems,
                              Set-DPIAwareness,
                              Capture-DesktopScreenshot