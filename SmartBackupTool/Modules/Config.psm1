# Config.psm1 - Configuration management functions

function Initialize-Configuration {
    [CmdletBinding()]
    param (
        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\config"),
        [string]$ProfileName = "Default"
    )

    $configFilePath = Join-Path -Path $ConfigPath -ChildPath "config.json"
    
    try {
        # Load main configuration
        if (Test-Path -Path $configFilePath -PathType Leaf) {
            $mainConfig = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
        } else {
            throw "Configuration file not found: $configFilePath"
        }

        # Check if the profile exists
        if (-not $mainConfig.Profiles.$ProfileName) {
            Write-Warning "Profile '$ProfileName' not found. Using default profile."
            $ProfileName = $mainConfig.DefaultProfileName
            
            # If default profile doesn't exist either, create it
            if (-not $mainConfig.Profiles.$ProfileName) {
                $mainConfig.Profiles.$ProfileName = @{
                    Description = "Default backup profile"
                    Incremental = $false
                    Compression = @{
                        Enabled = $false
                        Level = "Normal"
                    }
                }
                
                # Save updated configuration
                $mainConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8
            }
        }

        # Create a config object that combines main settings and profile-specific settings
        $config = [PSCustomObject]@{
            DefaultBackupRoot = $mainConfig.DefaultBackupRoot
            TempBackupRoot = $mainConfig.TempBackupRoot
            CurrentProfileName = $ProfileName
            ProfileSettings = $mainConfig.Profiles.$ProfileName
            EnableReviewMode = $mainConfig.EnableReviewMode
            EnableScreenshot = $mainConfig.EnableScreenshot
            DisableFirefoxBackup = $mainConfig.DisableFirefoxBackup
            EnableTestRestore = $mainConfig.EnableTestRestore
            TestModeEnabled = $mainConfig.TestModeEnabled -eq $true
            SavePath = $configFilePath
            
            # Additional properties for custom folders list
            CustomFoldersList = @()
            CustomFoldersPath = Join-Path -Path $ConfigPath -ChildPath "CustomFolders.json"
        }

        # Load custom folders if file exists
        if (Test-Path -Path $config.CustomFoldersPath -PathType Leaf) {
            $config.CustomFoldersList = Get-Content -Path $config.CustomFoldersPath -Raw | 
                                         ConvertFrom-Json -ErrorAction Stop
        }

        # Create a method to save configuration changes
        $config | Add-Member -MemberType ScriptMethod -Name "Save" -Value {
            # Save main configuration
            $mainConfig = Get-Content -Path $this.SavePath -Raw | ConvertFrom-Json
            $mainConfig.DefaultBackupRoot = $this.DefaultBackupRoot
            $mainConfig.TempBackupRoot = $this.TempBackupRoot
            $mainConfig.EnableReviewMode = $this.EnableReviewMode
            $mainConfig.EnableScreenshot = $this.EnableScreenshot
            $mainConfig.DisableFirefoxBackup = $this.DisableFirefoxBackup
            $mainConfig.EnableTestRestore = $this.EnableTestRestore
            $mainConfig.TestModeEnabled = $this.TestModeEnabled
            
            # Update profile settings
            $mainConfig.Profiles.($this.CurrentProfileName) = $this.ProfileSettings
            
            # Save updated config
            $mainConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $this.SavePath -Encoding UTF8
            
            # Save custom folders
            $this.CustomFoldersList | ConvertTo-Json -Depth 5 | 
                Set-Content -Path $this.CustomFoldersPath -Encoding UTF8
        }

        return $config
    }
    catch {
        Write-Error "Failed to initialize configuration: $_"
        throw
    }
}

function Get-BackupProfilesList {
    [CmdletBinding()]
    param (
        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\config")
    )
    
    $configFilePath = Join-Path -Path $ConfigPath -ChildPath "config.json"
    
    try {
        if (Test-Path -Path $configFilePath -PathType Leaf) {
            $config = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
            return $config.Profiles.PSObject.Properties.Name
        } else {
            Write-Warning "Configuration file not found: $configFilePath"
            return @("Default")
        }
    }
    catch {
        Write-Error "Failed to get profiles list: $_"
        return @("Default")
    }
}

function New-BackupProfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        
        [string]$Description = "Custom backup profile",
        
        [bool]$Incremental = $false,
        
        [bool]$EnableCompression = $false,
        
        [ValidateSet("Fastest", "Normal", "Maximum")]
        [string]$CompressionLevel = "Normal",
        
        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\config")
    )
    
    $configFilePath = Join-Path -Path $ConfigPath -ChildPath "config.json"
    
    try {
        if (Test-Path -Path $configFilePath -PathType Leaf) {
            $config = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
            
            # Check if profile already exists
            if ($config.Profiles.PSObject.Properties.Name -contains $ProfileName) {
                Write-Warning "Profile '$ProfileName' already exists. Use Update-BackupProfile to modify it."
                return $false
            }
            
            # Add new profile
            $newProfile = [PSCustomObject]@{
                Description = $Description
                Incremental = $Incremental
                Compression = [PSCustomObject]@{
                    Enabled = $EnableCompression
                    Level = $CompressionLevel
                }
            }
            
            # Add profile to config
            $config.Profiles | Add-Member -MemberType NoteProperty -Name $ProfileName -Value $newProfile
            
            # Save updated config
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8
            
            return $true
        } else {
            Write-Error "Configuration file not found: $configFilePath"
            return $false
        }
    }
    catch {
        Write-Error "Failed to create new profile: $_"
        return $false
    }
}

function Update-BackupProfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        
        [string]$Description,
        
        [bool]$Incremental,
        
        [bool]$EnableCompression,
        
        [ValidateSet("Fastest", "Normal", "Maximum")]
        [string]$CompressionLevel,
        
        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\config")
    )
    
    $configFilePath = Join-Path -Path $ConfigPath -ChildPath "config.json"
    
    try {
        if (Test-Path -Path $configFilePath -PathType Leaf) {
            $config = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
            
            # Check if profile exists
            if ($config.Profiles.PSObject.Properties.Name -notcontains $ProfileName) {
                Write-Error "Profile '$ProfileName' not found."
                return $false
            }
            
            # Update profile fields if provided
            if ($PSBoundParameters.ContainsKey('Description')) {
                $config.Profiles.$ProfileName.Description = $Description
            }
            
            if ($PSBoundParameters.ContainsKey('Incremental')) {
                $config.Profiles.$ProfileName.Incremental = $Incremental
            }
            
            if ($PSBoundParameters.ContainsKey('EnableCompression')) {
                $config.Profiles.$ProfileName.Compression.Enabled = $EnableCompression
            }
            
            if ($PSBoundParameters.ContainsKey('CompressionLevel')) {
                $config.Profiles.$ProfileName.Compression.Level = $CompressionLevel
            }
            
            # Save updated config
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8
            
            return $true
        } else {
            Write-Error "Configuration file not found: $configFilePath"
            return $false
        }
    }
    catch {
        Write-Error "Failed to update profile: $_"
        return $false
    }
}

function Remove-BackupProfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        
        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\config")
    )
    
    $configFilePath = Join-Path -Path $ConfigPath -ChildPath "config.json"
    
    try {
        if (Test-Path -Path $configFilePath -PathType Leaf) {
            $config = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
            
            # Check if profile exists
            if ($config.Profiles.PSObject.Properties.Name -notcontains $ProfileName) {
                Write-Error "Profile '$ProfileName' not found."
                return $false
            }
            
            # Prevent removing the default profile
            if ($ProfileName -eq $config.DefaultProfileName) {
                Write-Error "Cannot remove the default profile. Set a different profile as default first."
                return $false
            }
            
            # Convert to PowerShell object to allow removal of property
            $tempConfig = [PSCustomObject]@{
                DefaultBackupRoot = $config.DefaultBackupRoot
                TempBackupRoot = $config.TempBackupRoot
                DefaultProfileName = $config.DefaultProfileName
                EnableReviewMode = $config.EnableReviewMode
                EnableScreenshot = $config.EnableScreenshot
                DisableFirefoxBackup = $config.DisableFirefoxBackup
                EnableTestRestore = $config.EnableTestRestore
                TestModeEnabled = $config.TestModeEnabled
                Profiles = [PSCustomObject]@{}
            }
            
            # Copy all profiles except the one to remove
            foreach ($profile in $config.Profiles.PSObject.Properties) {
                if ($profile.Name -ne $ProfileName) {
                    $tempConfig.Profiles | Add-Member -MemberType NoteProperty -Name $profile.Name -Value $profile.Value
                }
            }
            
            # Save updated config
            $tempConfig | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8
            
            return $true
        } else {
            Write-Error "Configuration file not found: $configFilePath"
            return $false
        }
    }
    catch {
        Write-Error "Failed to remove profile: $_"
        return $false
    }
}

function Set-DefaultProfile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProfileName,
        
        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\config")
    )
    
    $configFilePath = Join-Path -Path $ConfigPath -ChildPath "config.json"
    
    try {
        if (Test-Path -Path $configFilePath -PathType Leaf) {
            $config = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
            
            # Check if profile exists
            if ($config.Profiles.PSObject.Properties.Name -notcontains $ProfileName) {
                Write-Error "Profile '$ProfileName' not found."
                return $false
            }
            
            # Update default profile
            $config.DefaultProfileName = $ProfileName
            
            # Save updated config
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8
            
            return $true
        } else {
            Write-Error "Configuration file not found: $configFilePath"
            return $false
        }
    }
    catch {
        Write-Error "Failed to set default profile: $_"
        return $false
    }
}

function Update-ConfigFile {
    [CmdletBinding()]
    param (
        [string]$ConfigPath = (Join-Path -Path $PSScriptRoot -ChildPath "..\config"),
        [string]$PropertyName,
        [object]$Value
    )
    
    $configFilePath = Join-Path -Path $ConfigPath -ChildPath "config.json"
    
    try {
        if (Test-Path -Path $configFilePath -PathType Leaf) {
            $config = Get-Content -Path $configFilePath -Raw | ConvertFrom-Json -ErrorAction Stop
            $config.$PropertyName = $Value
            $config | ConvertTo-Json -Depth 10 | Set-Content -Path $configFilePath -Encoding UTF8
            return $true
        } else {
            Write-Error "Configuration file not found: $configFilePath"
            return $false
        }
    }
    catch {
        Write-Error "Failed to update configuration file: $_"
        return $false
    }
}

# Export module functions
Export-ModuleMember -Function Initialize-Configuration, 
                              Get-BackupProfilesList, 
                              New-BackupProfile, 
                              Update-BackupProfile, 
                              Remove-BackupProfile, 
                              Set-DefaultProfile,
                              Update-ConfigFile