# CoreGUI.psm1 - Core GUI components and initialization

# Module globals
$script:mainForm = $null
$script:logStartY = 0
$script:mainLogBox = $null
$script:txtDestination = $null
$script:config = $null
$script:testModeIndicator = $null
$script:folderListCanvas = $null
$script:canvasState = $null
$script:folderList = @()

function Show-BackupGUI {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]$Config
    )
    # Store configuration globally
    $script:config = $Config

    # Create the main form
    $form = New-Object System.Windows.Forms.Form -Property @{
        Text = "Smart Backup Tool v2.0"
        Size = New-Object System.Drawing.Size(1360, 1150)
        StartPosition = "CenterScreen"
        AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
        KeyPreview = $true
        Icon = [System.Drawing.Icon]::ExtractAssociatedIcon([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
    }
    
    # Store form globally
    $script:mainForm = $form
    
    # Create UI components (these will be added by other modules)
    Add-DestinationControls
    
    # Initialize GUI modules
    Initialize-FolderListModule
    Initialize-ActionModule
    Initialize-ConfigModule

    # Load window position
    Load-WindowPosition
    
    # Initialize folder list
    Initialize-FolderList

    # Update test mode indicator
    Update-TestModeUI
    
    # Add form event handlers
    $form.Add_FormClosing({
        param($sender, $e)
        Save-WindowPosition
    })
    
    # Show the form as a dialog
    [void]$form.ShowDialog()
    
    # Clean up
    $form.Dispose()
}

function Add-DestinationControls {
    # Destination selection
    $lblDest = New-Object System.Windows.Forms.Label -Property @{
        Font = New-Object System.Drawing.Font("Segoe UI", 12)
        Text = "Backup Destination:"
        Location = New-Object System.Drawing.Point(20, 10)
        AutoSize = $true
    }
    
    $txtDest = New-Object System.Windows.Forms.TextBox -Property @{
        Font = New-Object System.Drawing.Font("Segoe UI", 11)
        Text = $script:config.DefaultBackupRoot
        Size = New-Object System.Drawing.Size(400, 25)
        Location = New-Object System.Drawing.Point(20, 50)
    }
    
    $btnBrowse = New-Object System.Windows.Forms.Button -Property @{
        Text = "Browse..."
        Size = New-Object System.Drawing.Size(100, 25)
        Location = New-Object System.Drawing.Point(430, 50)
    }
    
    $btnBrowse.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Select the main folder where backups should be stored"
        if (Test-Path $txtDest.Text -PathType Container) {
            $dlg.SelectedPath = $txtDest.Text
        }
        elseif (Test-Path $script:config.DefaultBackupRoot -PathType Container) {
            $dlg.SelectedPath = $script:config.DefaultBackupRoot
        }
        
        if ($dlg.ShowDialog($script:mainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $txtDest.Text = $dlg.SelectedPath
            # Update config
            $script:config.DefaultBackupRoot = $dlg.SelectedPath
            $script:config.Save()
        }
        
        $dlg.Dispose()
    })
    
    $script:mainForm.Controls.AddRange(@($lblDest, $txtDest, $btnBrowse))
    
    # Store for other functions to access
    $script:txtDestination = $txtDest
}

function Add-LogBox {
    # Create log box
    $logBoxHeight = 200
    $txtLog = New-Object System.Windows.Forms.TextBox -Property @{
        Font = New-Object System.Drawing.Font("Consolas", 10)
        Multiline = $true
        ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        ReadOnly = $true
        Location = New-Object System.Drawing.Point(20, $script:logStartY)
        Size = New-Object System.Drawing.Size($script:folderListCanvas.Width, $logBoxHeight)
        Anchor = (
            [System.Windows.Forms.AnchorStyles]::Bottom -bor
            [System.Windows.Forms.AnchorStyles]::Left -bor
            [System.Windows.Forms.AnchorStyles]::Right
        )
        HideSelection = $false
        BackColor = [System.Drawing.SystemColors]::Info
    }
    
    $script:mainForm.Controls.Add($txtLog)
    $script:mainLogBox = $txtLog

    # Add initial log message
    $script:mainLogBox.AppendText("Smart Backup Tool v2.0 Initialized. Ready.`r`n")
}

function Update-TestModeUI {
    if ($script:testModeIndicator) {
        $script:testModeIndicator.Visible = $script:config.TestModeEnabled
    }
}

function Load-WindowPosition {
    # Implement window position loading logic here
    # This can be expanded later to remember window position between sessions
}

function Save-WindowPosition {
    # Implement window position saving logic here
    # This can be expanded later to save window position between sessions
}

function Initialize-FolderList {
    # Load the folder list from configuration
    $script:folderList = @()
    
    # Check for custom folders saved in config
    if ($script:config.CustomFoldersList -and $script:config.CustomFoldersList.Count -gt 0) {
        $script:folderList = $script:config.CustomFoldersList
    }
    else {
        # Add default folders
        $knownFolders = Get-KnownBackupFolders
        foreach ($folder in $knownFolders) {
            Add-FolderToList $folder $true $false
        }
        
        # Add Firefox profile unless disabled
        if (-not $script:config.DisableFirefoxBackup) {
            $firefoxProfile = Get-FirefoxProfilePath
            if ($firefoxProfile) {
                Add-FolderToList $firefoxProfile $true $false
            }
        }
    }
    
    # Sort the list
    $script:folderList = $script:folderList | Sort-Object -Property Path
    
    # Update the UI
    Update-FolderListView
}

function Add-FolderToList {
    param(
        [string]$path,
        [bool]$isChecked,
        [bool]$isDefault
    )
    
    # Check if path already exists in the list (case-insensitive)
    if ($script:folderList.Path -contains $path) {
        Write-Verbose "Path '$path' already exists in the list. Skipping add."
        return
    }
    
    # Create the folder item and add it to the list
    $item = [PSCustomObject]@{
        Path = $path
        Checked = $isChecked
        Default = $isDefault
        Y = 0 # Will be set during drawing
        IsVisible = $false # Will be set during drawing
    }
    
    $script:folderList += $item
}

function Update-FolderListView {
    if ($null -ne $script:folderListCanvas) {
        $script:folderListCanvas.Invalidate()
    }
}

# Export module functions
Export-ModuleMember -Function Show-BackupGUI