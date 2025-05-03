# ConfigModule.psm1 - Settings panel and configuration UI (Part 1)

function Initialize-ConfigModule {
    # Add settings panels and config-related UI elements
    Add-SettingsPanel
    Add-TestModeControls
    Add-ProfileManagerLink
    Add-ScheduleManagerLink
}

function Add-SettingsPanel {
    # Create Panel
    $pnlSettings = New-Object System.Windows.Forms.Panel -Property @{
        Size = New-Object System.Drawing.Size(480, 180)
        BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
        Location = New-Object System.Drawing.Point(
            ([int]$script:folderListCanvas.Right + 20),
            [int]$script:folderListCanvas.Top
        )
    }
    
    # Create Title Label
    $lblSettingsTitle = New-Object System.Windows.Forms.Label -Property @{
        Text = "Backup Settings"
        Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        Location = New-Object System.Drawing.Point(10, 10)
        AutoSize = $true
    }
    
    # Profile Label and ComboBox
    $lblProfile = New-Object System.Windows.Forms.Label -Property @{
        Text = "Profile:"
        Location = New-Object System.Drawing.Point(10, 40)
        AutoSize = $true
    }
    
    $cboProfile = New-Object System.Windows.Forms.ComboBox -Property @{
        DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        Location = New-Object System.Drawing.Point(120, 40)
        Size = New-Object System.Drawing.Size(200, 25)
    }
    
    # Load profiles
    $profiles = Get-BackupProfilesList
    foreach ($profile in $profiles) {
        [void]$cboProfile.Items.Add($profile)
    }
    
    # Set selected profile
    $cboProfile.SelectedItem = $script:config.CurrentProfileName
    $cboProfile.Add_SelectedIndexChanged({
        $selectedProfile = $cboProfile.SelectedItem
        if ($selectedProfile -and $selectedProfile -ne $script:config.CurrentProfileName) {
            # Switch to new profile
            $script:config = Initialize-Configuration -ProfileName $selectedProfile
            
            # Update UI based on new profile
            $chkReviewMode.Checked = $script:config.EnableReviewMode
            $chkDisableFirefox.Checked = $script:config.DisableFirefoxBackup
            $chkScreenshot.Checked = $script:config.EnableScreenshot
            $chkTestRestore.Checked = $script:config.EnableTestRestore
            $chkIncrementalBackup.Checked = $script:config.ProfileSettings.Incremental
            $chkCompression.Checked = $script:config.ProfileSettings.Compression.Enabled
            
            # Update folder list
            Initialize-FolderList
            $script:mainLogBox.AppendText("Switched to profile: $selectedProfile`r`n")
        }
    })
    
    # Create Checkboxes
    $checkboxStartY = 70
    $checkboxSpacing = 25
    $chkReviewMode = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "Enable Review Mode (Temp Folder First)"
        AutoSize = $true
        Checked = $script:config.EnableReviewMode
        Location = New-Object System.Drawing.Point(10, $checkboxStartY)
    }
    
    $chkDisableFirefox = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "Disable Firefox Backup"
        AutoSize = $true
        Checked = $script:config.DisableFirefoxBackup
        Location = New-Object System.Drawing.Point(10, ($checkboxStartY + $checkboxSpacing))
    }
    
    $chkScreenshot = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "Include Desktop Screenshot"
        AutoSize = $true
        Checked = $script:config.EnableScreenshot
        Location = New-Object System.Drawing.Point(10, ($checkboxStartY + $checkboxSpacing * 2))
    }
    
    $chkTestRestore = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "Enable Test Restore Mode (No Files Copied)"
        AutoSize = $true
        Checked = $script:config.EnableTestRestore
        Location = New-Object System.Drawing.Point(10, ($checkboxStartY + $checkboxSpacing * 3))
    }
    
    # Add advanced options on the right side
    $advancedX = 250
    $chkIncrementalBackup = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "Incremental Backup"
        AutoSize = $true
        Checked = $script:config.ProfileSettings.Incremental
        Location = New-Object System.Drawing.Point($advancedX, $checkboxStartY)
    }
    
    $chkCompression = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "Enable Compression"
        AutoSize = $true
        Checked = $script:config.ProfileSettings.Compression.Enabled
        Location = New-Object System.Drawing.Point($advancedX, ($checkboxStartY + $checkboxSpacing))
    }
    
    # Add handler to save settings when checkboxes change
    $chkReviewMode.Add_CheckedChanged({
        $script:config.EnableReviewMode = $chkReviewMode.Checked
        $script:config.Save()
    })
    
    $chkDisableFirefox.Add_CheckedChanged({
        $script:config.DisableFirefoxBackup = $chkDisableFirefox.Checked
        $script:config.Save()
    })
    
    $chkScreenshot.Add_CheckedChanged({
        $script:config.EnableScreenshot = $chkScreenshot.Checked
        $script:config.Save()
    })
    
    $chkTestRestore.Add_CheckedChanged({
        $script:config.EnableTestRestore = $chkTestRestore.Checked
        $script:config.Save()
    })
    
    $chkIncrementalBackup.Add_CheckedChanged({
        $script:config.ProfileSettings.Incremental = $chkIncrementalBackup.Checked
        $script:config.Save()
    })
    
    $chkCompression.Add_CheckedChanged({
        $script:config.ProfileSettings.Compression.Enabled = $chkCompression.Checked
        $script:config.Save()
    })
    
    # Add all controls to the panel
    $pnlSettings.Controls.AddRange(@(
        $lblSettingsTitle,
        $lblProfile,
        $cboProfile,
        $chkReviewMode,
        $chkDisableFirefox,
        $chkScreenshot,
        $chkTestRestore,
        $chkIncrementalBackup,
        $chkCompression
    ))
    
    # Add the panel to the form
    $script:mainForm.Controls.Add($pnlSettings)
}

function Add-TestModeControls {
    # Add test mode panel to settings
    $testModePanel = New-Object System.Windows.Forms.Panel -Property @{
        BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        Size = New-Object System.Drawing.Size(480, 200)
        Location = New-Object System.Drawing.Point(
            ([int]$script:folderListCanvas.Right + 20),
            ([int]$script:folderListCanvas.Top + 190)
        )
        Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
    }
    
    $lblTestMode = New-Object System.Windows.Forms.Label -Property @{
        Text = "Test Mode Controls"
        Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        Location = New-Object System.Drawing.Point(10, 10)
        AutoSize = $true
    }
    
    $chkMasterTestMode = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "ENABLE TEST MODE (No actual file operations)"
        Location = New-Object System.Drawing.Point(10, 40)
        Size = New-Object System.Drawing.Size(300, 30)
        Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
        ForeColor = [System.Drawing.Color]::Red
        Checked = $script:config.TestModeEnabled
    }
    
    $chkMasterTestMode.Add_CheckedChanged({
        if ($chkMasterTestMode.Checked) {
            Enable-TestMode
        } else {
            Disable-TestMode
        }
    })
    
    $btnRunTests = New-Object System.Windows.Forms.Button -Property @{
        Text = "Run Automated Tests"
        Location = New-Object System.Drawing.Point(10, 80)
        Size = New-Object System.Drawing.Size(150, 30)
    }
    
    $btnRunTests.Add_Click({
        Run-AutomatedTests
    })
    
    $btnViewReport = New-Object System.Windows.Forms.Button -Property @{
        Text = "View Test Report"
        Location = New-Object System.Drawing.Point(170, 80)
        Size = New-Object System.Drawing.Size(150, 30)
    }
    
    $btnViewReport.Add_Click({
        Show-TestReport
    })
    
    $lblTestInfo = New-Object System.Windows.Forms.Label -Property @{
        Text = "Test mode simulates all operations without modifying any files." +
               "`r`nAutomated tests verify core functionality using simulations."
        Location = New-Object System.Drawing.Point(10, 120)
        Size = New-Object System.Drawing.Size(460, 50)
    }
    
    $testModePanel.Controls.AddRange(@(
        $lblTestMode,
        $chkMasterTestMode,
        $btnRunTests,
        $btnViewReport,
        $lblTestInfo
    ))
    
    # Add visual indicator when test mode is active
    $lblTestModeIndicator = New-Object System.Windows.Forms.Label -Property @{
        Text = "TEST MODE ACTIVE - NO ACTUAL FILE OPERATIONS WILL OCCUR"
        Location = New-Object System.Drawing.Point(20, $script:mainForm.ClientSize.Height - 40)
        Size = New-Object System.Drawing.Size(500, 20)
        ForeColor = [System.Drawing.Color]::Red
        Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        Visible = $script:config.TestModeEnabled
        Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left)
    }
    
    $script:testModeIndicator = $lblTestModeIndicator
    $script:mainForm.Controls.Add($testModePanel)
    $script:mainForm.Controls.Add($lblTestModeIndicator)
}

function Add-ProfileManagerLink {
    # Create a link label for profile management
    $lnkProfileManager = New-Object System.Windows.Forms.LinkLabel -Property @{
        Text = "Manage Backup Profiles"
        Location = New-Object System.Drawing.Point(
            ([int]$script:folderListCanvas.Right + 20),
            [int]$script:folderListCanvas.Top + 400
        )
        Size = New-Object System.Drawing.Size(200, 20)
        Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
    }
    
    $lnkProfileManager.Add_LinkClicked({
        Show-ProfileManager
    })
    
    $script:mainForm.Controls.Add($lnkProfileManager)
}

function Add-ScheduleManagerLink {
    # Create a link label for schedule management
    $lnkScheduleManager = New-Object System.Windows.Forms.LinkLabel -Property @{
        Text = "Manage Backup Schedule"
        Location = New-Object System.Drawing.Point(
            ([int]$script:folderListCanvas.Right + 20),
            [int]$script:folderListCanvas.Top + 430
        )
        Size = New-Object System.Drawing.Size(200, 20)
        Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right)
    }
    
    $lnkScheduleManager.Add_LinkClicked({
        Show-ScheduleManager
    })
    
    $script:mainForm.Controls.Add($lnkScheduleManager)
}

function Enable-TestMode {
    $script:config.TestModeEnabled = $true
    $script:config.Save()
    Update-TestModeUI
    $script:mainLogBox.AppendText("Test Mode Enabled - No actual file operations will occur.`r`n")
}

function Disable-TestMode {
    $script:config.TestModeEnabled = $false
    $script:config.Save()
    Update-TestModeUI
    $script:mainLogBox.AppendText("Test Mode Disabled - Normal file operations will occur.`r`n")
}

# Export module functions for Part 1
Export-ModuleMember -Function Initialize-ConfigModule, Enable-TestMode, Disable-TestMode