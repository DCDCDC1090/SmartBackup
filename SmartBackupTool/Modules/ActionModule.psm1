# ActionModule.psm1 - Action buttons and operations

function Initialize-ActionModule {
    # Add the action buttons and set up log box
    Add-ActionButtons
    Add-LogBox
}

function Add-ActionButtons {
    # Define button sizes and spacing
    $buttonWidth = 270
    $buttonHeight = 30
    $buttonHeightLarge = 40
    $buttonSpacingX = 10
    $buttonSpacingY = 5
    $buttonAreaStartY = $script:folderListCanvas.Bottom + 20
    
    # Scan Button
    $btnScan = New-Object System.Windows.Forms.Button -Property @{
        Text = "Scan for App-Linked Folders"
        Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
        Location = New-Object System.Drawing.Point(20, $buttonAreaStartY)
        Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left)
    }
    
    $btnScan.Add_Click({
        $script:mainLogBox.AppendText("Scanning for app-linked folders...`r`n")
        $script:mainForm.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
        $existingPaths = $script:folderList.Path
        $foundCount = 0
        
        try {
            $linkedFolders = Analyze-ProgramDependencies
            foreach ($p in $linkedFolders) {
                if (Test-Path $p -PathType Container) {
                    if ($existingPaths -notcontains $p) {
                        Add-FolderToList $p $true $false
                        $script:mainLogBox.AppendText(" Added: $p`r`n")
                        $foundCount++
                    }
                }
            }
            
            # Sort the list after adding
            $script:folderList = $script:folderList | Sort-Object -Property Path
            Update-FolderListView
            $script:mainLogBox.AppendText("Scan complete. Added $foundCount new folders.`r`n")
        }
        catch {
            $script:mainLogBox.AppendText("Error during scan: $($_.Exception.Message)`r`n")
        }
        finally {
            $script:mainForm.Cursor = [System.Windows.Forms.Cursors]::Default
        }
    })
    
    # Manual Add Button
    $btnManual = New-Object System.Windows.Forms.Button -Property @{
        Text = "Browse to Add Folder"
        Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
        Location = New-Object System.Drawing.Point((20 + $buttonWidth + $buttonSpacingX), $buttonAreaStartY)
        Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left)
    }
    
    $btnManual.Add_Click({
        $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
        $dlg.Description = "Select a folder to add to the backup list"
        
        # Set initial path if possible
        if ($script:folderList.Count -gt 0) {
            $lastPath = $script:folderList[-1].Path
            if (Test-Path $lastPath -PathType Container) {
                $dlg.SelectedPath = $lastPath
            }
        }
        elseif (Test-Path $script:txtDestination.Text -PathType Container) {
            $dlg.SelectedPath = $script:txtDestination.Text
        }
        
        if ($dlg.ShowDialog($script:mainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
            $p = $dlg.SelectedPath
            if ($script:folderList.Path -notcontains $p) {
                Add-FolderToList $p $true $false
                $script:folderList = $script:folderList | Sort-Object -Property Path
                Update-FolderListView
                $script:mainLogBox.AppendText("Manually added: $p`r`n")
            }
            else {
                $script:mainLogBox.AppendText("Folder already in list: $p`r`n")
            }
        }
        
        $dlg.Dispose()
    })
    
    # Remove Button
    $btnRemove = New-Object System.Windows.Forms.Button -Property @{
        Text = "Remove Selected Folder from List"
        Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
        Location = New-Object System.Drawing.Point(
            (20 + ($buttonWidth + $buttonSpacingX) * 2),
            $buttonAreaStartY
        )
        Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left)
    }
    
    $btnRemove.Add_Click({
        if ($script:canvasState.SelectedItemIndex -ge 0 -and
            $script:canvasState.SelectedItemIndex -lt $script:folderList.Count) {
            $itemToRemove = $script:folderList[$script:canvasState.SelectedItemIndex]
            $pathToRemove = $itemToRemove.Path
            
            $confirmRemove = [System.Windows.Forms.MessageBox]::Show(
                $script:mainForm,
                "Remove '$pathToRemove' from the list?`n(This does not delete the actual folder on disk)",
                "Confirm Removal",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Question
            )
            
            if ($confirmRemove -eq 'Yes') {
                $wasDefault = $itemToRemove.Default
                $originalIndex = $script:canvasState.SelectedItemIndex
                
                # Remove from the list
                $script:folderList = $script:folderList | Where-Object { $_.Path -ne $pathToRemove }
                $script:canvasState.SelectedItemIndex = -1
                $script:canvasState.HoveredItemIndex = -1
                
                # Update defaults if needed
                if ($wasDefault) {
                    # Update custom folders in config
                    $script:config.CustomFoldersList = $script:folderList
                    $script:config.Save()
                    $script:mainLogBox.AppendText(
                        "Removed '$pathToRemove' and updated defaults.`r`n"
                    )
                }
                else {
                    $script:mainLogBox.AppendText("Removed '$pathToRemove' from list.`r`n")
                }
                
                # Try to select the item at the same index, or the last item
                if ($originalIndex -lt $script:folderList.Count) {
                    $script:canvasState.SelectedItemIndex = $originalIndex
                }
                elseif ($script:folderList.Count -gt 0) {
                    $script:canvasState.SelectedItemIndex = $script:folderList.Count - 1
                }
                
                Update-FolderListView
            }
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                $script:mainForm,
                "Please select a folder in the list to remove.",
                "No Selection",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    })
    
    # Move to next row
    $currentY = $buttonAreaStartY + $buttonHeight + $buttonSpacingY
    
    # Backup Button
    $btnBackup = New-Object System.Windows.Forms.Button -Property @{
        Text = "Run Backup"
        Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeightLarge)
        Location = New-Object System.Drawing.Point(20, $currentY)
        Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left)
        BackColor = [System.Drawing.Color]::LightGreen
    }
    
    $btnBackup.Add_Click({
        Run-Backup
    })
    
    # Restore Button
    $btnRestore = New-Object System.Windows.Forms.Button -Property @{
        Text = "Run Restore"
        Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeightLarge)
        Location = New-Object System.Drawing.Point(
            (20 + $buttonWidth + $buttonSpacingX),
            $currentY
        )
        Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
        Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left)
        BackColor = [System.Drawing.Color]::LightCoral
    }
    
    $btnRestore.Add_Click({
        Run-Restore
    })
    
    # Manage Defaults Button
    $btnManage = New-Object System.Windows.Forms.Button -Property @{
        Text = "Manage Default Folders"
        Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
        Location = New-Object System.Drawing.Point(
            (20 + ($buttonWidth + $buttonSpacingX) * 2),
            ($currentY + ($buttonHeightLarge - $buttonHeight))
        )
        Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left)
    }
    
    $btnManage.Add_Click({
        Show-DefaultFoldersManager
    })
    
    # Move to next row
    $currentY = $currentY + $buttonHeightLarge + $buttonSpacingY
    
    # Copy Log Button
    $btnCopy = New-Object System.Windows.Forms.Button -Property @{
        Text = "Copy Log to Clipboard"
        Size = New-Object System.Drawing.Size($buttonWidth, $buttonHeight)
        Location = New-Object System.Drawing.Point(20, $currentY)
        Anchor = ([System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left)
    }
    
    $btnCopy.Add_Click({
        if ($script:mainLogBox.TextLength -gt 0) {
            try {
                [System.Windows.Forms.Clipboard]::SetText($script:mainLogBox.Text)
                [System.Windows.Forms.MessageBox]::Show(
                    $script:mainForm,
                    "Log content copied to clipboard.",
                    "Log Copied",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Information
                )
            }
            catch {
                $script:mainLogBox.AppendText("ERROR copying log to clipboard: $($_.Exception.Message)`r`n")
                [System.Windows.Forms.MessageBox]::Show(
                    $script:mainForm,
                    "Could not copy log to clipboard.`n$($_.Exception.Message)",
                    "Copy Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
            }
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                $script:mainForm,
                "Log is empty.",
                "Nothing to Copy",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
        }
    })
    
    # Add all buttons to the form
    $script:mainForm.Controls.AddRange(@($btnScan, $btnManual, $btnRemove, $btnBackup, $btnRestore, $btnManage, $btnCopy))
    
    # Store the log start position for use in Add-LogBox
    $script:logStartY = $currentY + $buttonHeight + $buttonSpacingY
}

function Run-Backup {
    # Validate destination path
    $backupDestination = $script:txtDestination.Text
    if (-not (Test-Path $backupDestination -PathType Container)) {
        [System.Windows.Forms.MessageBox]::Show(
            $script:mainForm,
            "Invalid destination path. Please select an existing folder.",
            "Error",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        return
    }
    
    # Confirm backup
    $confirmation = [System.Windows.Forms.MessageBox]::Show(
        $script:mainForm,
        "Start backup to '$backupDestination'?",
        "Confirm Backup",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($confirmation -ne "Yes") {
        $script:mainLogBox.AppendText("Backup cancelled by user.`r`n")
        return
    }
    
    # Get checked items
    $selectedFolders = $script:folderList | Where-Object { $_.Checked }
    if ($selectedFolders.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            $script:mainForm,
            "No folders selected to back up.",
            "Warning",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        return
    }
    
    # Clear log box
    $script:mainLogBox.Clear()
    $script:mainLogBox.AppendText("Starting backup...`r`n")
    $script:mainForm.Refresh()
    
    # Create a progress form
    $progressForm = New-Object System.Windows.Forms.Form -Property @{
        Text = "Backup Progress"
        Size = New-Object System.Drawing.Size(400, 150)
        StartPosition = "CenterParent"
        FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        ControlBox = $false
        MaximizeBox = $false
        MinimizeBox = $false
    }
    
    $lblStatus = New-Object System.Windows.Forms.Label -Property @{
        Location = New-Object System.Drawing.Point(20, 20)
        Size = New-Object System.Drawing.Size(360, 20)
        Text = "Preparing backup..."
    }
    
    $progressBar = New-Object System.Windows.Forms.ProgressBar -Property @{
        Location = New-Object System.Drawing.Point(20, 50)
        Size = New-Object System.Drawing.Size(360, 20)
        Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        Minimum = 0
        Maximum = 100
        Value = 0
    }
    
    $btnCancel = New-Object System.Windows.Forms.Button -Property @{
        Location = New-Object System.Drawing.Point(150, 80)
        Size = New-Object System.Drawing.Size(100, 30)
        Text = "Cancel"
        DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    }
    
    $progressForm.Controls.AddRange(@($lblStatus, $progressBar, $btnCancel))
    $progressForm.CancelButton = $btnCancel
    
    # Show progress form (non-modal)
    $progressForm.Show()
    $script:mainForm.Update()
    
    # Define log function
    $logFunction = {
        param($message)
        $script:mainLogBox.AppendText("$message`r`n")
        $script:mainLogBox.ScrollToCaret()
        $script:mainForm.Update()
    }
    
    # Define progress function
    $progressFunction = {
        param($current, $total, $statusMessage)
        if ($progressForm.IsDisposed) { return }
        $percent = [math]::Round(($current / $total) * 100)
        
        # Update UI on the UI thread
        $progressForm.Invoke([Action]{
            $progressBar.Value = $percent
            $lblStatus.Text = "$statusMessage ($percent%)"
        })
    }
    
    # Define completion function
    $completeFunction = {
        param($success, $resultPath, $errors)
        
        # Close progress form if it hasn't been already
        if (-not $progressForm.IsDisposed) {
            $progressForm.Invoke([Action]{ $progressForm.Close() })
        }
        
        if ($success) {
            $message = "Backup completed successfully.`r`n"
            if ($resultPath) {
                $message += "Location: $resultPath`r`n"
            }
            $icon = [System.Windows.Forms.MessageBoxIcon]::Information
        }
        else {
            $message = "Backup completed with errors. See log for details.`r`n"
            if ($errors -and $errors.Count -gt 0) {
                foreach ($error in $errors) {
                    $message += "- $error`r`n"
                }
            }
            $icon = [System.Windows.Forms.MessageBoxIcon]::Warning
        }
        
        $logFunction.Invoke($message)
        [System.Windows.Forms.MessageBox]::Show(
            $script:mainForm,
            $message,
            "Backup Complete",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            $icon
        )
    }
    
    # Start the backup operation
    Start-BackupOperation -Config $script:config `
        -FoldersToBackup $selectedFolders `
        -DestinationPath $backupDestination `
        -LogFunction $logFunction `
        -ProgressFunction $progressFunction `
        -CompleteFunction $completeFunction
    
    # Handle review mode if needed
    if ($script:config.EnableReviewMode) {
        # Wait for review form to close
        $progressForm.Close()
        $reviewResult = [System.Windows.Forms.MessageBox]::Show(
            $script:mainForm,
            "Temporary backup complete. Review the contents and keep this backup?",
            "Review Backup",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
        $keepBackup = ($reviewResult -eq "Yes")
        Complete-ReviewBackup -KeepBackup $keepBackup
    }
}

function Run-Restore {
    # Ask user to select the backup folder
    $browseDialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $browseDialog.Description = "Select the specific Backup folder (e.g., Backup_YYYY-MM-DD_HH-MM-SS) to restore FROM"
    
    # Start browsing in the current backup destination folder
    $startBrowsePath = $script:txtDestination.Text
    if (-not (Test-Path $startBrowsePath -PathType Container)) {
        $startBrowsePath = $script:config.DefaultBackupRoot
    }
    
    if (Test-Path $startBrowsePath -PathType Container) {
        $browseDialog.SelectedPath = $startBrowsePath
    }
    
    if ($browseDialog.ShowDialog($script:mainForm) -eq [System.Windows.Forms.DialogResult]::OK) {
        $selectedBackupPath = $browseDialog.SelectedPath
        
        # Check if it looks like a valid backup folder
        if (Test-Path (Join-Path $selectedBackupPath "BackupDetails.log") -PathType Leaf) {
            # Get the list of folders to restore
            $restoreFolders = Get-RestoreFolderList $selectedBackupPath
            if ($restoreFolders -ne $null -and $restoreFolders.Count -gt 0) {
                # Show restore selection dialog
                $selectedItems = Show-RestoreFolderSelector $restoreFolders
                if ($selectedItems -ne $null -and $selectedItems.Count -gt 0) {
                    # Run the restore
                    Start-RestoreOperation $selectedBackupPath $selectedItems $script:config.EnableTestRestore
                }
                else {
                    $script:mainLogBox.AppendText("Restore cancelled by user during folder selection.`r`n")
                }
            }
            else {
                [System.Windows.Forms.MessageBox]::Show(
                    $script:mainForm,
                    "No items found in the selected backup or error reading the backup details.",
                    "No Items to Restore",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
            }
        }
        else {
            [System.Windows.Forms.MessageBox]::Show(
                $script:mainForm,
                "The selected folder '$selectedBackupPath' does not appear to be a valid backup source (missing BackupDetails.log).",
                "Invalid Restore Source",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            $script:mainLogBox.AppendText("Restore cancelled: Invalid source selected.`r`n")
        }
    }
    else {
        $script:mainLogBox.AppendText("Restore cancelled by user during source folder selection.`r`n")
    }
    
    $browseDialog.Dispose()
}

function Show-RestoreFolderSelector {
    param (
        [Parameter(Mandatory=$true)]
        [array]$FolderList
    )
    
    # Create a form for folder selection
    $restoreForm = New-Object System.Windows.Forms.Form -Property @{
        Text = "Select Folders to Restore"
        Size = New-Object System.Drawing.Size(700, 500)
        StartPosition = "CenterParent"
        FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::Sizable
        MinimumSize = New-Object System.Drawing.Size(500, 300)
    }
    
    # Create a CheckedListBox
    $checkedListBox = New-Object System.Windows.Forms.CheckedListBox -Property @{
        CheckOnClick = $true
        Dock = [System.Windows.Forms.DockStyle]::Fill
        Font = New-Object System.Drawing.Font("Segoe UI", 9)
    }
    
    # Add items
    foreach ($folder in $FolderList) {
        $displayText = "$($folder.Name) -> $($folder.OriginalPath)"
        $index = $checkedListBox.Items.Add($displayText)
        $checkedListBox.SetItemChecked($index, $folder.Checked)
        
        # Store the full folder object in the Tag property
        $checkedListBox.Items[$index] = New-Object System.Windows.Forms.ListViewItem -Property @{
            Text = $displayText
            Tag = $folder
        }
    }
    
    # Create buttons panel
    $buttonPanel = New-Object System.Windows.Forms.Panel -Property @{
        Dock = [System.Windows.Forms.DockStyle]::Bottom
        Height = 50
    }
    
    $btnCheckAll = New-Object System.Windows.Forms.Button -Property @{
        Text = "Check All"
        Location = New-Object System.Drawing.Point(10, 10)
        Size = New-Object System.Drawing.Size(80, 30)
    }
    
    $btnUncheckAll = New-Object System.Windows.Forms.Button -Property @{
        Text = "Uncheck All"
        Location = New-Object System.Drawing.Point(100, 10)
        Size = New-Object System.Drawing.Size(80, 30)
    }
    
    $btnRestore = New-Object System.Windows.Forms.Button -Property @{
        Text = "Restore Selected"
        Location = New-Object System.Drawing.Point(450, 10)
        Size = New-Object System.Drawing.Size(120, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::OK
        Anchor = ([System.Windows.Forms.AnchorStyles]::Right)
    }
    
    $btnCancel = New-Object System.Windows.Forms.Button -Property @{
        Text = "Cancel"
        Location = New-Object System.Drawing.Point(580, 10)
        Size = New-Object System.Drawing.Size(80, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        Anchor = ([System.Windows.Forms.AnchorStyles]::Right)
    }
    
    # Add buttons to panel
    $buttonPanel.Controls.AddRange(@($btnCheckAll, $btnUncheckAll, $btnRestore, $btnCancel))
    
    # Add handlers
    $btnCheckAll.Add_Click({
        for ($i = 0; $i -lt $checkedListBox.Items.Count; $i++) {
            $checkedListBox.SetItemChecked($i, $true)
        }
    })
    
    $btnUncheckAll.Add_Click({
        for ($i = 0; $i -lt $checkedListBox.Items.Count; $i++) {
            $checkedListBox.SetItemChecked($i, $false)
        }
    })
    
    # Add controls to form
    $restoreForm.Controls.Add($checkedListBox)
    $restoreForm.Controls.Add($buttonPanel)
    
    # Set form properties
    $restoreForm.AcceptButton = $btnRestore
    $restoreForm.CancelButton = $btnCancel
    
    # Show the form
    $result = $restoreForm.ShowDialog($script:mainForm)
    
    # Process result
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        # Update checked state on original FolderList
        for ($i = 0; $i -lt $checkedListBox.Items.Count; $i++) {
            $item = $checkedListBox.Items[$i]
            $folder = $item.Tag
            $folder.Checked = $checkedListBox.GetItemChecked($i)
        }
        
        $restoreForm.Dispose()
        return $FolderList
    }
    
    $restoreForm.Dispose()
    return $null
}

# Export module functions
Export-ModuleMember -Function Initialize-ActionModule, Run-Backup, Run-Restore, Show-RestoreFolderSelector