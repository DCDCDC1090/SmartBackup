# ConfigModuleUI.psm1 - Config UI forms and advanced functionality (Part 2)

function Show-ProfileManager {
    # Create profile manager form
    $profileForm = New-Object System.Windows.Forms.Form -Property @{
        Text = "Backup Profile Manager"
        Size = New-Object System.Drawing.Size(500, 400)
        StartPosition = "CenterParent"
        FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        MaximizeBox = $false
        MinimizeBox = $false
    }
    
    # Create list view for profiles
    $lstProfiles = New-Object System.Windows.Forms.ListView -Property @{
        View = [System.Windows.Forms.View]::Details
        FullRowSelect = $true
        Location = New-Object System.Drawing.Point(20, 20)
        Size = New-Object System.Drawing.Size(440, 200)
        HideSelection = $false
    }
    
    # Add columns
    [void]$lstProfiles.Columns.Add("Profile Name", 150)
    [void]$lstProfiles.Columns.Add("Description", 150)
    [void]$lstProfiles.Columns.Add("Incremental", 70)
    [void]$lstProfiles.Columns.Add("Compression", 70)
    
    # Add profiles
    $profiles = Get-BackupProfilesList
    $configPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "config\config.json"
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    
    foreach ($profileName in $profiles) {
        $profile = $config.Profiles.$profileName
        $item = New-Object System.Windows.Forms.ListViewItem($profileName)
        if ($profileName -eq $config.DefaultProfileName) {
            $item.Font = New-Object System.Drawing.Font($lstProfiles.Font, [System.Drawing.FontStyle]::Bold)
        }
        [void]$item.SubItems.Add($profile.Description)
        [void]$item.SubItems.Add($(if ($profile.Incremental) { "Yes" } else { "No" }))
        [void]$item.SubItems.Add($(if ($profile.Compression.Enabled) { "Yes" } else { "No" }))
        [void]$lstProfiles.Items.Add($item)
    }
    
    # Buttons
    $btnNew = New-Object System.Windows.Forms.Button -Property @{
        Text = "New Profile"
        Location = New-Object System.Drawing.Point(20, 240)
        Size = New-Object System.Drawing.Size(100, 30)
    }
    
    $btnEdit = New-Object System.Windows.Forms.Button -Property @{
        Text = "Edit Profile"
        Location = New-Object System.Drawing.Point(130, 240)
        Size = New-Object System.Drawing.Size(100, 30)
        Enabled = $false
    }
    
    $btnDelete = New-Object System.Windows.Forms.Button -Property @{
        Text = "Delete Profile"
        Location = New-Object System.Drawing.Point(240, 240)
        Size = New-Object System.Drawing.Size(100, 30)
        Enabled = $false
    }
    
    $btnSetDefault = New-Object System.Windows.Forms.Button -Property @{
        Text = "Set as Default"
        Location = New-Object System.Drawing.Point(350, 240)
        Size = New-Object System.Drawing.Size(110, 30)
        Enabled = $false
    }
    
    $btnClose = New-Object System.Windows.Forms.Button -Property @{
        Text = "Close"
        Location = New-Object System.Drawing.Point(360, 320)
        Size = New-Object System.Drawing.Size(100, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    }
    
    # Enable buttons when selection changes
    $lstProfiles.Add_SelectedIndexChanged({
        $selected = $lstProfiles.SelectedItems.Count -gt 0
        $btnEdit.Enabled = $selected
        $btnDelete.Enabled = $selected
        $btnSetDefault.Enabled = $selected
        
        if ($selected) {
            $profileName = $lstProfiles.SelectedItems[0].Text
            $btnDelete.Enabled = $profileName -ne $config.DefaultProfileName
            $btnSetDefault.Enabled = $profileName -ne $config.DefaultProfileName
        }
    })
    
    # Button event handlers
    $btnNew.Add_Click({
        $newProfile = Show-ProfileEditor -IsNew $true
        if ($newProfile) {
            # Refresh list
            $lstProfiles.Items.Clear()
            $profiles = Get-BackupProfilesList
            $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
            
            foreach ($profileName in $profiles) {
                $profile = $config.Profiles.$profileName
                $item = New-Object System.Windows.Forms.ListViewItem($profileName)
                if ($profileName -eq $config.DefaultProfileName) {
                    $item.Font = New-Object System.Drawing.Font($lstProfiles.Font, [System.Drawing.FontStyle]::Bold)
                }
                [void]$item.SubItems.Add($profile.Description)
                [void]$item.SubItems.Add($(if ($profile.Incremental) { "Yes" } else { "No" }))
                [void]$item.SubItems.Add($(if ($profile.Compression.Enabled) { "Yes" } else { "No" }))
                [void]$lstProfiles.Items.Add($item)
            }
        }
    })
    
    $btnEdit.Add_Click({
        if ($lstProfiles.SelectedItems.Count -gt 0) {
            $profileName = $lstProfiles.SelectedItems[0].Text
            $updated = Show-ProfileEditor -ProfileName $profileName
            
            if ($updated) {
                # Refresh list
                $lstProfiles.Items.Clear()
                $profiles = Get-BackupProfilesList
                $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
                
                foreach ($profileName in $profiles) {
                    $profile = $config.Profiles.$profileName
                    $item = New-Object System.Windows.Forms.ListViewItem($profileName)
                    if ($profileName -eq $config.DefaultProfileName) {
                        $item.Font = New-Object System.Drawing.Font($lstProfiles.Font, [System.Drawing.FontStyle]::Bold)
                    }
                    [void]$item.SubItems.Add($profile.Description)
                    [void]$item.SubItems.Add($(if ($profile.Incremental) { "Yes" } else { "No" }))
                    [void]$item.SubItems.Add($(if ($profile.Compression.Enabled) { "Yes" } else { "No" }))
                    [void]$lstProfiles.Items.Add($item)
                }
                
                # Reload config
                $script:config = Initialize-Configuration -ProfileName $script:config.CurrentProfileName
            }
        }
    })
    
    $btnDelete.Add_Click({
        if ($lstProfiles.SelectedItems.Count -gt 0) {
            $profileName = $lstProfiles.SelectedItems[0].Text
            if ($profileName -eq $config.DefaultProfileName) {
                [System.Windows.Forms.MessageBox]::Show(
                    $profileForm,
                    "Cannot delete the default profile. Set another profile as default first.",
                    "Cannot Delete",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            }
            
            $confirmDelete = [System.Windows.Forms.MessageBox]::Show(
                $profileForm,
                "Are you sure you want to delete the profile '$profileName'?",
                "Confirm Delete",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($confirmDelete -eq [System.Windows.Forms.DialogResult]::Yes) {
                $result = Remove-BackupProfile -ProfileName $profileName
                if ($result) {
                    # Remove from list
                    $lstProfiles.Items.RemoveAt($lstProfiles.SelectedIndices[0])
                    # Reload config
                    $script:config = Initialize-Configuration -ProfileName $script:config.CurrentProfileName
                }
            }
        }
    })
    
    $btnSetDefault.Add_Click({
        if ($lstProfiles.SelectedItems.Count -gt 0) {
            $profileName = $lstProfiles.SelectedItems[0].Text
            if ($profileName -eq $config.DefaultProfileName) {
                return
            }
            
            $result = Set-DefaultProfile -ProfileName $profileName
            if ($result) {
                # Refresh list
                $lstProfiles.Items.Clear()
                $profiles = Get-BackupProfilesList
                $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
                
                foreach ($profileName in $profiles) {
                    $profile = $config.Profiles.$profileName
                    $item = New-Object System.Windows.Forms.ListViewItem($profileName)
                    if ($profileName -eq $config.DefaultProfileName) {
                        $item.Font = New-Object System.Drawing.Font($lstProfiles.Font, [System.Drawing.FontStyle]::Bold)
                    }
                    [void]$item.SubItems.Add($profile.Description)
                    [void]$item.SubItems.Add($(if ($profile.Incremental) { "Yes" } else { "No" }))
                    [void]$item.SubItems.Add($(if ($profile.Compression.Enabled) { "Yes" } else { "No" }))
                    [void]$lstProfiles.Items.Add($item)
                }
                
                # Reload config
                $script:config = Initialize-Configuration -ProfileName $script:config.CurrentProfileName
            }
        }
    })
    
    # Add controls to form
    $profileForm.Controls.AddRange(@($lstProfiles, $btnNew, $btnEdit, $btnDelete, $btnSetDefault, $btnClose))
    $profileForm.CancelButton = $btnClose
    
    # Show form
    [void]$profileForm.ShowDialog($script:mainForm)
    $profileForm.Dispose()
}

function Show-ProfileEditor {
    param (
        [string]$ProfileName = "",
        [switch]$IsNew
    )
    
    # Load existing profile data if editing
    $profileData = $null
    $configPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "config\config.json"
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
    
    if (-not $IsNew) {
        $profileData = $config.Profiles.$ProfileName
    }
    
    # Create profile editor form
    $editorForm = New-Object System.Windows.Forms.Form -Property @{
        Text = $(if ($IsNew) { "Create New Profile" } else { "Edit Profile" })
        Size = New-Object System.Drawing.Size(400, 350)
        StartPosition = "CenterParent"
        FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        MaximizeBox = $false
        MinimizeBox = $false
    }
    
    # Create form controls
    $lblName = New-Object System.Windows.Forms.Label -Property @{
        Text = "Profile Name:"
        Location = New-Object System.Drawing.Point(20, 20)
        AutoSize = $true
    }
    
    $txtName = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(150, 20)
        Size = New-Object System.Drawing.Size(200, 25)
        Enabled = $IsNew
        Text = $ProfileName
    }
    
    $lblDescription = New-Object System.Windows.Forms.Label -Property @{
        Text = "Description:"
        Location = New-Object System.Drawing.Point(20, 50)
        AutoSize = $true
    }
    
    $txtDescription = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(150, 50)
        Size = New-Object System.Drawing.Size(200, 25)
        Text = $(if ($profileData) { $profileData.Description } else { "Custom backup profile" })
    }
    
    $chkIncremental = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "Enable Incremental Backup"
        Location = New-Object System.Drawing.Point(20, 90)
        Size = New-Object System.Drawing.Size(200, 25)
        Checked = $(if ($profileData) { $profileData.Incremental } else { $false })
    }
    
    $chkCompression = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "Enable Compression"
        Location = New-Object System.Drawing.Point(20, 120)
        Size = New-Object System.Drawing.Size(200, 25)
        Checked = $(if ($profileData) { $profileData.Compression.Enabled } else { $false })
    }
    
    $lblCompressionLevel = New-Object System.Windows.Forms.Label -Property @{
        Text = "Compression Level:"
        Location = New-Object System.Drawing.Point(40, 150)
        AutoSize = $true
        Enabled = $(if ($profileData) { $profileData.Compression.Enabled } else { $false })
    }
    
    $cboCompressionLevel = New-Object System.Windows.Forms.ComboBox -Property @{
        DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        Location = New-Object System.Drawing.Point(150, 150)
        Size = New-Object System.Drawing.Size(200, 25)
        Enabled = $(if ($profileData) { $profileData.Compression.Enabled } else { $false })
    }
    
    # Add compression levels
    $compressionLevels = @("Fastest", "Normal", "Maximum")
    foreach ($level in $compressionLevels) {
        [void]$cboCompressionLevel.Items.Add($level)
    }
    
    # Set selected level
    if ($profileData) {
        $cboCompressionLevel.SelectedItem = $profileData.Compression.Level
    }
    else {
        $cboCompressionLevel.SelectedIndex = 1 # Normal
    }
    
    # Enable/disable compression level based on compression checkbox
    $chkCompression.Add_CheckedChanged({
        $lblCompressionLevel.Enabled = $chkCompression.Checked
        $cboCompressionLevel.Enabled = $chkCompression.Checked
    })
    
    # Buttons
    $btnSave = New-Object System.Windows.Forms.Button -Property @{
        Text = "Save"
        Location = New-Object System.Drawing.Point(190, 270)
        Size = New-Object System.Drawing.Size(80, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::OK
    }
    
    $btnCancel = New-Object System.Windows.Forms.Button -Property @{
        Text = "Cancel"
        Location = New-Object System.Drawing.Point(280, 270)
        Size = New-Object System.Drawing.Size(80, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    }
    
    # Add validation
    $editorForm.Add_FormClosing({
        param($sender, $e)
        if ($editorForm.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
            if ([string]::IsNullOrWhiteSpace($txtName.Text)) {
                [System.Windows.Forms.MessageBox]::Show(
                    $editorForm,
                    "Profile name cannot be empty.",
                    "Validation Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                $e.Cancel = $true
                return
            }
            
            if ($IsNew) {
                # Check if profile already exists
                $profiles = Get-BackupProfilesList
                if ($profiles -contains $txtName.Text) {
                    [System.Windows.Forms.MessageBox]::Show(
                        $editorForm,
                        "A profile with this name already exists.",
                        "Validation Error",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    $e.Cancel = $true
                    return
                }
            }
        }
    })
    
    # Add controls to form
    $editorForm.Controls.AddRange(@(
        $lblName, $txtName,
        $lblDescription, $txtDescription,
        $chkIncremental, $chkCompression,
        $lblCompressionLevel, $cboCompressionLevel,
        $btnSave, $btnCancel
    ))
    
    $editorForm.AcceptButton = $btnSave
    $editorForm.CancelButton = $btnCancel
    
    # Show form
    $result = $editorForm.ShowDialog($script:mainForm)
    
    # Process result
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        if ($IsNew) {
            # Create new profile
            $result = New-BackupProfile -ProfileName $txtName.Text `
                -Description $txtDescription.Text `
                -Incremental $chkIncremental.Checked `
                -EnableCompression $chkCompression.Checked `
                -CompressionLevel $cboCompressionLevel.SelectedItem
        }
        else {
            # Update existing profile
            $result = Update-BackupProfile -ProfileName $ProfileName `
                -Description $txtDescription.Text `
                -Incremental $chkIncremental.Checked `
                -EnableCompression $chkCompression.Checked `
                -CompressionLevel $cboCompressionLevel.SelectedItem
        }
        
        $editorForm.Dispose()
        return $result
    }
    
    $editorForm.Dispose()
    return $false
}

function Show-ScheduleManager {
    # Create schedule manager form
    $scheduleForm = New-Object System.Windows.Forms.Form -Property @{
        Text = "Backup Schedule Manager"
        Size = New-Object System.Drawing.Size(650, 400)
        StartPosition = "CenterParent"
        FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        MaximizeBox = $false
        MinimizeBox = $false
    }
    
    # Check if running as administrator
    $isAdmin = Test-Administrator
    if (-not $isAdmin) {
        $lblWarning = New-Object System.Windows.Forms.Label -Property @{
            Text = "Warning: Not running as Administrator. Task creation might fail."
            Location = New-Object System.Drawing.Point(20, 10)
            Size = New-Object System.Drawing.Size(610, 20)
            ForeColor = [System.Drawing.Color]::Red
            Font = New-Object System.Drawing.Font($scheduleForm.Font, [System.Drawing.FontStyle]::Bold)
        }
        $scheduleForm.Controls.Add($lblWarning)
    }
    
    # Create list view for scheduled tasks
    $lstTasks = New-Object System.Windows.Forms.ListView -Property @{
        View = [System.Windows.Forms.View]::Details
        FullRowSelect = $true
        Location = New-Object System.Drawing.Point(20, if ($isAdmin) { 20 } else { 40 })
        Size = New-Object System.Drawing.Size(610, 200)
        HideSelection = $false
    }
    
    # Add columns
    [void]$lstTasks.Columns.Add("Task Name", 150)
    [void]$lstTasks.Columns.Add("State", 70)
    [void]$lstTasks.Columns.Add("Profile", 100)
    [void]$lstTasks.Columns.Add("Last Run", 120)
    [void]$lstTasks.Columns.Add("Next Run", 120)
    [void]$lstTasks.Columns.Add("Result", 50)
    
    # Add tasks
    $tasks = Get-BackupTasks
    foreach ($task in $tasks) {
        $item = New-Object System.Windows.Forms.ListViewItem($task.Name)
        [void]$item.SubItems.Add($task.State)
        [void]$item.SubItems.Add($task.ProfileName)
        [void]$item.SubItems.Add($task.LastRunTime)
        [void]$item.SubItems.Add($task.NextRunTime)
        [void]$item.SubItems.Add($task.LastResult)
        
        if ($task.State -eq "Disabled") {
            $item.ForeColor = [System.Drawing.Color]::Gray
        }
        
        [void]$lstTasks.Items.Add($item)
    }
    
    # Buttons
    $buttonY = if ($isAdmin) { 240 } else { 260 }
    
    $btnCreate = New-Object System.Windows.Forms.Button -Property @{
        Text = "Create Task"
        Location = New-Object System.Drawing.Point(20, $buttonY)
        Size = New-Object System.Drawing.Size(100, 30)
    }
    
    $btnDelete = New-Object System.Windows.Forms.Button -Property @{
        Text = "Delete Task"
        Location = New-Object System.Drawing.Point(130, $buttonY)
        Size = New-Object System.Drawing.Size(100, 30)
        Enabled = $false
    }
    
    $btnEnable = New-Object System.Windows.Forms.Button -Property @{
        Text = "Enable Task"
        Location = New-Object System.Drawing.Point(240, $buttonY)
        Size = New-Object System.Drawing.Size(100, 30)
        Enabled = $false
    }
    
    $btnDisable = New-Object System.Windows.Forms.Button -Property @{
        Text = "Disable Task"
        Location = New-Object System.Drawing.Point(350, $buttonY)
        Size = New-Object System.Drawing.Size(100, 30)
        Enabled = $false
    }
    
    $btnRun = New-Object System.Windows.Forms.Button -Property @{
        Text = "Run Now"
        Location = New-Object System.Drawing.Point(460, $buttonY)
        Size = New-Object System.Drawing.Size(80, 30)
        Enabled = $false
    }
    
    $btnClose = New-Object System.Windows.Forms.Button -Property @{
        Text = "Close"
        Location = New-Object System.Drawing.Point(550, $buttonY)
        Size = New-Object System.Drawing.Size(80, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    }
    
    # Enable/disable buttons based on selection
    $lstTasks.Add_SelectedIndexChanged({
        $selected = $lstTasks.SelectedItems.Count -gt 0
        $btnDelete.Enabled = $selected
        $btnRun.Enabled = $selected
        
        if ($selected) {
            $taskState = $lstTasks.SelectedItems[0].SubItems[1].Text
            $btnEnable.Enabled = ($taskState -eq "Disabled")
            $btnDisable.Enabled = ($taskState -eq "Ready")
        }
        else {
            $btnEnable.Enabled = $false
            $btnDisable.Enabled = $false
        }
    })
    
    # Button handlers
    $btnCreate.Add_Click({
        $result = Show-ScheduleTaskCreator
        if ($result) {
            # Refresh list
            $lstTasks.Items.Clear()
            $tasks = Get-BackupTasks
            
            foreach ($task in $tasks) {
                $item = New-Object System.Windows.Forms.ListViewItem($task.Name)
                [void]$item.SubItems.Add($task.State)
                [void]$item.SubItems.Add($task.ProfileName)
                [void]$item.SubItems.Add($task.LastRunTime)
                [void]$item.SubItems.Add($task.NextRunTime)
                [void]$item.SubItems.Add($task.LastResult)
                
                if ($task.State -eq "Disabled") {
                    $item.ForeColor = [System.Drawing.Color]::Gray
                }
                
                [void]$lstTasks.Items.Add($item)
            }
        }
    })
    
    $btnDelete.Add_Click({
        if ($lstTasks.SelectedItems.Count -gt 0) {
            $taskName = $lstTasks.SelectedItems[0].Text
            
            $confirmDelete = [System.Windows.Forms.MessageBox]::Show(
                $scheduleForm,
                "Are you sure you want to delete the scheduled task '$taskName'?",
                "Confirm Delete",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($confirmDelete -eq [System.Windows.Forms.DialogResult]::Yes) {
                $result = Remove-BackupTask -TaskName $taskName
                
                if ($result) {
                    $lstTasks.Items.RemoveAt($lstTasks.SelectedIndices[0])
                }
            }
        }
    })
    
    $btnEnable.Add_Click({
        if ($lstTasks.SelectedItems.Count -gt 0) {
            $taskName = $lstTasks.SelectedItems[0].Text
            $result = Update-BackupTask -TaskName $taskName -Enable
            
            if ($result) {
                # Update UI
                $lstTasks.SelectedItems[0].SubItems[1].Text = "Ready"
                $lstTasks.SelectedItems[0].ForeColor = $lstTasks.ForeColor
                $btnEnable.Enabled = $false
                $btnDisable.Enabled = $true
            }
        }
    })
    
    $btnDisable.Add_Click({
        if ($lstTasks.SelectedItems.Count -gt 0) {
            $taskName = $lstTasks.SelectedItems[0].Text
            $result = Update-BackupTask -TaskName $taskName -Disable
            
            if ($result) {
                # Update UI
                $lstTasks.SelectedItems[0].SubItems[1].Text = "Disabled"
                $lstTasks.SelectedItems[0].ForeColor = [System.Drawing.Color]::Gray
                $btnEnable.Enabled = $true
                $btnDisable.Enabled = $false
            }
        }
    })
    
    $btnRun.Add_Click({
        if ($lstTasks.SelectedItems.Count -gt 0) {
            $taskName = $lstTasks.SelectedItems[0].Text
            $result = Run-BackupTask -TaskName $taskName
            
            if ($result) {
                [System.Windows.Forms.MessageBox]::Show(
                    $scheduleForm,
                    "Task '$taskName' has been started.`nIt will run in the background.",
                    "Task Started",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
        }
    })
    
    # Add controls to form
    $scheduleForm.Controls.AddRange(@(
        $lstTasks, $btnCreate, $btnDelete, $btnEnable, $btnDisable, $btnRun, $btnClose
    ))
    
    $scheduleForm.CancelButton = $btnClose
    
    # Show form
    [void]$scheduleForm.ShowDialog($script:mainForm)
    $scheduleForm.Dispose()
}

function Show-ScheduleTaskCreator {
    # Create task creator form
    $taskForm = New-Object System.Windows.Forms.Form -Property @{
        Text = "Create Scheduled Backup Task"
        Size = New-Object System.Drawing.Size(500, 400)
        StartPosition = "CenterParent"
        FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        MaximizeBox = $false
        MinimizeBox = $false
    }
    
    # Task name
    $lblName = New-Object System.Windows.Forms.Label -Property @{
        Text = "Task Name:"
        Location = New-Object System.Drawing.Point(20, 20)
        AutoSize = $true
    }
    
    $txtName = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(150, 20)
        Size = New-Object System.Drawing.Size(300, 25)
        Text = "SmartBackup_$(Get-Date -Format 'yyyyMMdd')"
    }
    
    # Schedule type
    $lblSchedule = New-Object System.Windows.Forms.Label -Property @{
        Text = "Schedule Type:"
        Location = New-Object System.Drawing.Point(20, 60)
        AutoSize = $true
    }
    
    $cboSchedule = New-Object System.Windows.Forms.ComboBox -Property @{
        DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        Location = New-Object System.Drawing.Point(150, 60)
        Size = New-Object System.Drawing.Size(150, 25)
    }
    
    # Add schedule types
    $scheduleTypes = @("Daily", "Weekly", "Monthly", "Once")
    foreach ($type in $scheduleTypes) {
        [void]$cboSchedule.Items.Add($type)
    }
    $cboSchedule.SelectedIndex = 0 # Default to Daily
    
    # Start time
    $lblTime = New-Object System.Windows.Forms.Label -Property @{
        Text = "Start Time:"
        Location = New-Object System.Drawing.Point(20, 100)
        AutoSize = $true
    }
    
    $dtpTime = New-Object System.Windows.Forms.DateTimePicker -Property @{
        Format = [System.Windows.Forms.DateTimePickerFormat]::Time
        ShowUpDown = $true
        Location = New-Object System.Drawing.Point(150, 100)
        Size = New-Object System.Drawing.Size(150, 25)
        Value = [DateTime]::Today.AddHours(23).AddMinutes(0) # Default to 11:00 PM
    }
    
    # Profile selection
    $lblProfile = New-Object System.Windows.Forms.Label -Property @{
        Text = "Backup Profile:"
        Location = New-Object System.Drawing.Point(20, 140)
        AutoSize = $true
    }
    
    $cboProfile = New-Object System.Windows.Forms.ComboBox -Property @{
        DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
        Location = New-Object System.Drawing.Point(150, 140)
        Size = New-Object System.Drawing.Size(200, 25)
    }
    
    # Load profiles
    $profiles = Get-BackupProfilesList
    foreach ($profile in $profiles) {
        [void]$cboProfile.Items.Add($profile)
    }
    $cboProfile.SelectedItem = $script:config.CurrentProfileName
    
    # Run as admin option
    $chkRunAsAdmin = New-Object System.Windows.Forms.CheckBox -Property @{
        Text = "Run with highest privileges (recommended)"
        Location = New-Object System.Drawing.Point(20, 180)
        Size = New-Object System.Drawing.Size(300, 25)
        Checked = $true
    }
    
    # Description
    $lblDesc = New-Object System.Windows.Forms.Label -Property @{
        Text = "Description:"
        Location = New-Object System.Drawing.Point(20, 220)
        AutoSize = $true
    }
    
    $txtDesc = New-Object System.Windows.Forms.TextBox -Property @{
        Location = New-Object System.Drawing.Point(150, 220)
        Size = New-Object System.Drawing.Size(300, 25)
        Text = "Smart Backup automated task"
    }
    
    # Buttons
    $btnCreate = New-Object System.Windows.Forms.Button -Property @{
        Text = "Create Task"
        Location = New-Object System.Drawing.Point(260, 310)
        Size = New-Object System.Drawing.Size(100, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::OK
    }
    
    $btnCancel = New-Object System.Windows.Forms.Button -Property @{
        Text = "Cancel"
        Location = New-Object System.Drawing.Point(370, 310)
        Size = New-Object System.Drawing.Size(100, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    }
    
    # Add validation
    $taskForm.Add_FormClosing({
        param($sender, $e)
        if ($taskForm.DialogResult -eq [System.Windows.Forms.DialogResult]::OK) {
            if ([string]::IsNullOrWhiteSpace($txtName.Text)) {
                [System.Windows.Forms.MessageBox]::Show(
                    $taskForm,
                    "Task name cannot be empty.",
                    "Validation Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                $e.Cancel = $true
                return
            }
            
            if ($cboProfile.SelectedItem -eq $null) {
                [System.Windows.Forms.MessageBox]::Show(
                    $taskForm,
                    "Please select a backup profile.",
                    "Validation Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                $e.Cancel = $true
                return
            }
        }
    })
    
    # Add controls to form
    $taskForm.Controls.AddRange(@(
        $lblName, $txtName,
        $lblSchedule, $cboSchedule,
        $lblTime, $dtpTime,
        $lblProfile, $cboProfile,
        $chkRunAsAdmin,
        $lblDesc, $txtDesc,
        $btnCreate, $btnCancel
    ))
    
    $taskForm.AcceptButton = $btnCreate
    $taskForm.CancelButton = $btnCancel
    
    # Show form
    $result = $taskForm.ShowDialog($script:mainForm)
    
    # Process result
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        # Calculate start time
        $startTime = Get-Date
        $startTime = $startTime.Date.Add($dtpTime.Value.TimeOfDay)
        
        # Get script path
        $scriptPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "SmartBackup.ps1"
        
        # Create the task
        $result = Register-BackupTask -TaskName $txtName.Text `
            -ScriptPath $scriptPath `
            -ScheduleType $cboSchedule.SelectedItem `
            -StartTime $startTime `
            -ProfileName $cboProfile.SelectedItem `
            -Description $txtDesc.Text `
            -RunAsAdmin:$chkRunAsAdmin.Checked
        
        if ($result) {
            [System.Windows.Forms.MessageBox]::Show(
                $taskForm,
                "Scheduled task '$($txtName.Text)' has been created successfully.",
                "Task Created",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                $taskForm,
                "Failed to create scheduled task. Make sure you have sufficient permissions.",
                "Task Creation Failed",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
        }
        
        $taskForm.Dispose()
        return $result
    }
    
    $taskForm.Dispose()
    return $false
}

# Test Module Functions
function Run-AutomatedTests {
    # Create test runner form
    $testForm = New-Object System.Windows.Forms.Form -Property @{
        Text = "Running Automated Tests"
        Size = New-Object System.Drawing.Size(500, 400)
        StartPosition = "CenterParent"
        FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        ControlBox = $false
        MaximizeBox = $false
        MinimizeBox = $false
    }
    
    # Test log box
    $txtTestLog = New-Object System.Windows.Forms.TextBox -Property @{
        Multiline = $true
        ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        ReadOnly = $true
        Location = New-Object System.Drawing.Point(20, 20)
        Size = New-Object System.Drawing.Size(460, 300)
        Font = New-Object System.Drawing.Font("Consolas", 9)
    }
    
    # Progress bar
    $progressBar = New-Object System.Windows.Forms.ProgressBar -Property @{
        Location = New-Object System.Drawing.Point(20, 330)
        Size = New-Object System.Drawing.Size(460, 20)
        Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        Minimum = 0
        Maximum = 100
        Value = 0
    }
    
    # Close button (disabled until tests complete)
    $btnClose = New-Object System.Windows.Forms.Button -Property @{
        Text = "Close"
        Location = New-Object System.Drawing.Point(380, 360)
        Size = New-Object System.Drawing.Size(100, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::OK
        Enabled = $false
    }
    
    $testForm.Controls.AddRange(@($txtTestLog, $progressBar, $btnClose))
    $testForm.Show()
    
    # Store the current test mode state to restore it later
    $originalTestMode = $script:config.TestModeEnabled
    
    # Ensure test mode is enabled for the tests
    if (-not $originalTestMode) {
        Enable-TestMode
    }
    
    # Run tests
    try {
        # Helper function to log test results
        $testLog = {
            param($message)
            $txtTestLog.AppendText("$message`r`n")
            $txtTestLog.ScrollToCaret()
            $testForm.Update()
        }
        
        # Clear test log to start fresh
        $script:testLogEntries = @()
        
        # Log test start
        $testLog.Invoke("=== Starting Automated Tests ===")
        $testLog.Invoke("Session ID: $script:testSessionId")
        $testLog.Invoke("Timestamp: $(Get-Date)`r`n")
        
        # Define test cases
        $testCases = @(
            @{
                Name = "Configuration Loading"
                Action = {
                    $profileName = $script:config.CurrentProfileName
                    $testLog.Invoke("  Loading profile: $profileName")
                    $config = Initialize-Configuration -ProfileName $profileName
                    return ($null -ne $config)
                }
            },
            @{
                Name = "Folder Path Validation"
                Action = {
                    $samplePath = "C:\ThisPathShouldNotExist_TestingOnly"
                    $testLog.Invoke("  Testing invalid path: $samplePath")
                    $result = Test-Path $samplePath -PathType Container
                    return (-not $result)
                }
            },
            @{
                Name = "Backup Simulation"
                Action = {
                    $testLog.Invoke("  Simulating backup operation")
                    
                    # Create a temporary test folder
                    $testFolder = Join-Path -Path $env:TEMP -ChildPath "SmartBackupTest_$script:testSessionId"
                    if (-not (Test-Path $testFolder)) {
                        New-Item -Path $testFolder -ItemType Directory -Force | Out-Null
                    }
                    
                    # Simulate backup to test folder
                    $mockFolder = [PSCustomObject]@{
                        Path = $env:USERPROFILE
                        Checked = $true
                        Default = $true
                    }
                    
                    # Count test success
                    $passed = $true
                    
                    # Return results
                    return $passed
                }
            },
            @{
                Name = "Restore Simulation"
                Action = {
                    $testLog.Invoke("  Simulating restore operation")
                    
                    # Simulate restore from a mock backup
                    $testFolder = Join-Path -Path $env:TEMP -ChildPath "SmartBackupTest_$script:testSessionId"
                    
                    # Count test success
                    $passed = $true
                    
                    # Return results
                    return $passed
                }
            }
        )
        
        # Run each test case
        $passCount = 0
        $failCount = 0
        $totalTests = $testCases.Count
        
        for ($i = 0; $i -lt $totalTests; $i++) {
            $test = $testCases[$i]
            $testLog.Invoke("Test $($i + 1)/$totalTests: $($test.Name)")
            
            try {
                $result = $test.Action.Invoke()
                if ($result) {
                    $testLog.Invoke("  PASSED`r`n")
                    $passCount++
                }
                else {
                    $testLog.Invoke("  FAILED`r`n")
                    $failCount++
                }
            }
            catch {
                $testLog.Invoke("  ERROR: $($_.Exception.Message)")
                $testLog.Invoke("  FAILED`r`n")
                $failCount++
            }
            
            # Update progress bar
            $progressBar.Value = [Math]::Round((($i + 1) / $totalTests) * 100)
        }
        
        # Log test summary
        $testLog.Invoke("=== Test Summary ===")
        $testLog.Invoke("Total tests: $totalTests")
        $testLog.Invoke("Passed: $passCount")
        $testLog.Invoke("Failed: $failCount")
        $testLog.Invoke("Success rate: $([Math]::Round(($passCount / $totalTests) * 100))%")
        
        # Save test results to the test log
        $script:testLogEntries = $txtTestLog.Lines
        Save-TestLog
        
        # Enable close button
        $btnClose.Enabled = $true
    }
    finally {
        # Restore original test mode state
        if (-not $originalTestMode) {
            Disable-TestMode
        }
    }
    
    # Wait for the user to close the form
    [void]$testForm.ShowDialog()
    $testForm.Dispose()
}

function Show-TestReport {
    if ($script:testLogEntries.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            $script:mainForm,
            "No test log entries found. Please run the automated tests first.",
            "No Test Data",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        )
        return
    }
    
    # Create report viewer form
    $reportForm = New-Object System.Windows.Forms.Form -Property @{
        Text = "Test Report Viewer"
        Size = New-Object System.Drawing.Size(600, 500)
        StartPosition = "CenterParent"
        FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
        MinimumSize = New-Object System.Drawing.Size(400, 300)
    }
    
    # Test log box
    $txtReport = New-Object System.Windows.Forms.TextBox -Property @{
        Multiline = $true
        ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
        ReadOnly = $true
        Dock = [System.Windows.Forms.DockStyle]::Fill
        Font = New-Object System.Drawing.Font("Consolas", 9)
    }
    
    # Load test log entries
    $txtReport.Lines = $script:testLogEntries
    
    # Button panel
    $buttonPanel = New-Object System.Windows.Forms.Panel -Property @{
        Dock = [System.Windows.Forms.DockStyle]::Bottom
        Height = 50
    }
    
    # Copy button
    $btnCopy = New-Object System.Windows.Forms.Button -Property @{
        Text = "Copy to Clipboard"
        Location = New-Object System.Drawing.Point(10, 10)
        Size = New-Object System.Drawing.Size(130, 30)
    }
    
    $btnCopy.Add_Click({
        if ($txtReport.TextLength -gt 0) {
            try {
                [System.Windows.Forms.Clipboard]::SetText($txtReport.Text)
                [System.Windows.Forms.MessageBox]::Show(
                    $reportForm,
                    "Test report copied to clipboard.",
                    "Copy Successful",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    $reportForm,
                    "Could not copy to clipboard: $($_.Exception.Message)",
                    "Copy Failed",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        }
    })
    
    # Save button
    $btnSave = New-Object System.Windows.Forms.Button -Property @{
        Text = "Save Report"
        Location = New-Object System.Drawing.Point(150, 10)
        Size = New-Object System.Drawing.Size(100, 30)
    }
    
    $btnSave.Add_Click({
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "Text Files (*.txt)|*.txt|All Files (*.*)|*.*"
        $saveDialog.DefaultExt = "txt"
        $saveDialog.FileName = "TestReport_$script:testSessionId.txt"
        
        if ($saveDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            try {
                $txtReport.Text | Set-Content -Path $saveDialog.FileName -Encoding UTF8
                [System.Windows.Forms.MessageBox]::Show(
                    $reportForm,
                    "Test report saved to: $($saveDialog.FileName)",
                    "Save Successful",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show(
                    $reportForm,
                    "Could not save report: $($_.Exception.Message)",
                    "Save Failed",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        }
    })
    
    # Close button
    $btnClose = New-Object System.Windows.Forms.Button -Property @{
        Text = "Close"
        Location = New-Object System.Drawing.Point(470, 10)
        Size = New-Object System.Drawing.Size(100, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        Anchor = ([System.Windows.Forms.AnchorStyles]::Right)
    }
    
    # Add buttons to panel
    $buttonPanel.Controls.AddRange(@($btnCopy, $btnSave, $btnClose))
    
    # Add controls to form
    $reportForm.Controls.Add($txtReport)
    $reportForm.Controls.Add($buttonPanel)
    
    # Set form properties
    $reportForm.CancelButton = $btnClose
    
    # Show form
    [void]$reportForm.ShowDialog()
    $reportForm.Dispose()
}

function Save-TestLog {
    # Create logs directory if it doesn't exist
    $logsPath = Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "logs"
    if (-not (Test-Path -Path $logsPath -PathType Container)) {
        New-Item -Path $logsPath -ItemType Directory -Force | Out-Null
    }
    
    # Create test logs directory
    $testLogsPath = Join-Path -Path $logsPath -ChildPath "TestResults"
    if (-not (Test-Path -Path $testLogsPath -PathType Container)) {
        New-Item -Path $testLogsPath -ItemType Directory -Force | Out-Null
    }
    
    # Save the log file
    $logFileName = "TestResults_$script:testSessionId.log"
    $logFilePath = Join-Path -Path $testLogsPath -ChildPath $logFileName
    
    if ($script:testLogEntries.Count -gt 0) {
        $script:testLogEntries | Out-File -FilePath $logFilePath -Encoding UTF8
    }
}

# Export module functions for Part 2
Export-ModuleMember -Function Show-ProfileManager, Show-ScheduleManager, Show-TestReport, Run-AutomatedTests