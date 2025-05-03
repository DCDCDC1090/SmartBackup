# FolderListModule.psm1 - Folder list management components

function Initialize-FolderListModule {
    # Add the folder list view to the main form
    Add-FolderListView
}

function Add-FolderListView {
    # Constants
    $itemHeight = 24
    $headerHeight = 26
    $checkWidth = 110
    $defaultWidth = 100
    $folderPathWidth = 580
    $scrollbarWidth = [System.Windows.Forms.SystemInformation]::VerticalScrollBarWidth
    $canvasRequiredWidth = $checkWidth + $defaultWidth + $folderPathWidth + $scrollbarWidth + 5
    
    # Create the canvas panel
    $canvas = New-Object System.Windows.Forms.Panel -Property @{
        Size = New-Object System.Drawing.Size($canvasRequiredWidth, 600)
        Location = New-Object System.Drawing.Point(20, 90)
        BackColor = [System.Drawing.Color]::White
        BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
        Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor
                 [System.Windows.Forms.AnchorStyles]::Bottom -bor
                 [System.Windows.Forms.AnchorStyles]::Left)
    }
    
    # Enable double buffering for smooth drawing
    try {
        $combinedStyles = [int][System.Windows.Forms.ControlStyles]::OptimizedDoubleBuffer -bor
                         [int][System.Windows.Forms.ControlStyles]::AllPaintingInWmPaint
        $canvas.GetType().GetMethod(
            "SetStyle",
            [System.Reflection.BindingFlags]'NonPublic,Instance'
        ).Invoke($canvas, @($combinedStyles, $true))
    }
    catch {
        Write-Warning "Could not set DoubleBuffered style on canvas panel: $($_.Exception.Message)"
    }
    
    # Canvas state (stored in script scope for event handlers)
    $script:canvasState = @{
        Canvas = $canvas
        ItemHeight = $itemHeight
        HeaderHeight = $headerHeight
        CheckWidth = $checkWidth
        DefaultWidth = $defaultWidth
        FolderPathWidth = $folderPathWidth
        ScrollbarWidth = $scrollbarWidth
        ScrollOffset = 0
        MaxScroll = 0
        SelectedItemIndex = -1
        HoveredItemIndex = -1
        MouseDownOnScrollbar = $false
        MouseDownOnItem = $false
        DragStartY = 0
        ScrollbarHeight = 0
        ScrollbarY = 0
        ScrollRatio = 0
        ScrollThumbHeight = 0
    }
    
    # Add paint event handler
    $canvas.Add_Paint({
        param($sender, $e)
        if ($null -eq $e -or $null -eq $e.Graphics) { return }
        $g = $e.Graphics
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
        $state = $script:canvasState
        
        # Use try-finally for GDI resources
        $itemFont = $null
        $highlightBrush = $null
        $selectedBrush = $null
        $stringFormat = $null
        $stringFormatHeader = $null
        $fontHeader = $null
        $textBrush = [System.Drawing.Brushes]::Black
        $bgBrush = [System.Drawing.Brushes]::White
        $headerBgBrush = [System.Drawing.Brushes]::LightGray
        $linePen = [System.Drawing.Pens]::LightGray
        $headerBorderPen = [System.Drawing.Pens]::Black
        
        try {
            $g.Clear($bgBrush.Color)
            
            # Draw Header
            $headerRect = New-Object System.Drawing.Rectangle(0, 0, $canvas.Width, $state.HeaderHeight)
            $g.FillRectangle($headerBgBrush, $headerRect)
            $g.DrawRectangle($headerBorderPen, 0, 0, $canvas.Width - 1, $state.HeaderHeight - 1)
            
            $stringFormat = New-Object System.Drawing.StringFormat
            $stringFormat.LineAlignment = [System.Drawing.StringAlignment]::Center
            $stringFormat.Trimming = [System.Drawing.StringTrimming]::EllipsisCharacter
            
            $fontHeader = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
            $stringFormatHeader = $stringFormat.Clone()
            $stringFormatHeader.Alignment = [System.Drawing.StringAlignment]::Center
            
            # Header Text
            $includeRectF = New-Object System.Drawing.RectangleF(
                [float]5,
                [float]0,
                [float]($state.CheckWidth - 5),
                [float]$state.HeaderHeight
            )
            $g.DrawString("Backup?", $fontHeader, $textBrush, $includeRectF, $stringFormatHeader)
            
            $defaultRectHeaderF = New-Object System.Drawing.RectangleF(
                [float]$state.CheckWidth,
                [float]0,
                [float]$state.DefaultWidth,
                [float]$state.HeaderHeight
            )
            $g.DrawString("Default", $fontHeader, $textBrush, $defaultRectHeaderF, $stringFormatHeader)
            
            $pathHeaderX = [float]($state.CheckWidth + $state.DefaultWidth)
            $pathRectHeaderF = New-Object System.Drawing.RectangleF(
                $pathHeaderX,
                [float]0,
                [float]$state.FolderPathWidth,
                [float]$state.HeaderHeight
            )
            $g.DrawString("Folder Path", $fontHeader, $textBrush, $pathRectHeaderF, $stringFormatHeader)
            
            # Calculate Scroll Parameters
            $totalContentHeight = $script:folderList.Count * $state.ItemHeight
            $viewableHeight = $canvas.Height - $state.HeaderHeight
            $state.MaxScroll = [Math]::Max(0, $totalContentHeight - $viewableHeight)
            $state.ScrollOffset = [Math]::Max(0, [Math]::Min($state.MaxScroll, $state.ScrollOffset))
            
            # Draw Items
            $itemFont = New-Object System.Drawing.Font("Segoe UI", 10)
            $highlightBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 240, 255))
            $selectedBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, 220, 255))
            $currentFolderPathWidth = [float]$state.FolderPathWidth
            
            for ($i = 0; $i -lt $script:folderList.Count; $i++) {
                $item = $script:folderList[$i]
                $y = ($i * $state.ItemHeight) - $state.ScrollOffset + $state.HeaderHeight
                $item.Y = $y
                
                if (($y + $state.ItemHeight) -gt $state.HeaderHeight -and $y -lt $canvas.Height) {
                    $item.IsVisible = $true
                    $itemRectWidth = [int]($canvas.Width - $state.ScrollbarWidth)
                    $itemRect = New-Object System.Drawing.Rectangle(
                        [int]0,
                        [int]$y,
                        $itemRectWidth,
                        [int]$state.ItemHeight
                    )
                    
                    # Background Highlighting
                    if ($i -eq $state.SelectedItemIndex) {
                        $g.FillRectangle($selectedBrush, $itemRect)
                    }
                    elseif ($i -eq $state.HoveredItemIndex) {
                        $g.FillRectangle($highlightBrush, $itemRect)
                    }
                    
                    # Draw Checkbox
                    $checkRectY = [int]($y + ($state.ItemHeight - 16) / 2)
                    $checkRect = New-Object System.Drawing.Rectangle([int]5, $checkRectY, [int]16, [int]16)
                    $checkBoxState = if ($item.Checked) {
                        [System.Windows.Forms.VisualStyles.CheckBoxState]::CheckedNormal
                    }
                    else {
                        [System.Windows.Forms.VisualStyles.CheckBoxState]::UncheckedNormal
                    }
                    
                    if ([System.Windows.Forms.Application]::RenderWithVisualStyles) {
                        [System.Windows.Forms.VisualStyles.VisualStyleRenderer]::DrawCheckBox(
                            $g,
                            $checkRect,
                            $checkBoxState
                        )
                    }
                    else {
                        $buttonState = if ($item.Checked) {
                            [System.Windows.Forms.ButtonState]::Checked
                        }
                        else {
                            [System.Windows.Forms.ButtonState]::Normal
                        }
                        [System.Windows.Forms.ControlPaint]::DrawCheckBox($g, $checkRect, $buttonState)
                    }
                    
                    # Draw Default Mark
                    $defaultText = if ($item.Default) { "DEFAULT" } else { "" }
                    $defaultItemX = [float]$state.CheckWidth
                    $defaultRectF = New-Object System.Drawing.RectangleF(
                        $defaultItemX,
                        [float]$y,
                        [float]$state.DefaultWidth,
                        [float]$state.ItemHeight
                    )
                    $g.DrawString($defaultText, $itemFont, $textBrush, $defaultRectF, $stringFormat)
                    
                    # Draw Folder Path
                    $pathItemX = [float]($state.CheckWidth + $state.DefaultWidth)
                    $pathRectF = New-Object System.Drawing.RectangleF(
                        $pathItemX,
                        [float]$y,
                        $currentFolderPathWidth,
                        [float]$state.ItemHeight
                    )
                    $g.DrawString($item.Path, $itemFont, $textBrush, $pathRectF, $stringFormat)
                    
                    # Draw Separator Line
                    $lineY = [int]($y + $state.ItemHeight - 1)
                    $lineWidth = [int]($canvas.Width - $state.ScrollbarWidth)
                    $g.DrawLine($linePen, [int]0, $lineY, $lineWidth, $lineY)
                }
                else {
                    $item.IsVisible = $false
                }
            }
            
            # Draw Scrollbar
            if ($state.MaxScroll -gt 0) {
                $scrollBarX = [int]($canvas.Width - $state.ScrollbarWidth)
                $scrollBarRect = New-Object System.Drawing.Rectangle(
                    $scrollBarX,
                    [int]$state.HeaderHeight,
                    [int]$state.ScrollbarWidth,
                    [int]$viewableHeight
                )
                $g.FillRectangle([System.Drawing.SystemBrushes]::ControlLight, $scrollBarRect)
                
                $state.ScrollRatio = $viewableHeight / $totalContentHeight
                $state.ScrollThumbHeight = [Math]::Max(
                    20,
                    $viewableHeight * $state.ScrollRatio
                )
                
                $scrollThumbY = 0
                if ($state.MaxScroll -gt 0) {
                    $scrollThumbY = $state.HeaderHeight + (
                        $state.ScrollOffset / $state.MaxScroll * ($viewableHeight - $state.ScrollThumbHeight)
                    )
                }
                else {
                    $scrollThumbY = $state.HeaderHeight
                }
                
                $scrollThumbY = [Math]::Max(
                    $state.HeaderHeight,
                    [Math]::Min(
                        $state.HeaderHeight + $viewableHeight - $state.ScrollThumbHeight,
                        $scrollThumbY
                    )
                )
                
                $state.ScrollbarY = $scrollThumbY
                $state.ScrollbarHeight = $state.ScrollThumbHeight
                
                $thumbX = [int]($canvas.Width - $state.ScrollbarWidth + 2)
                $thumbW = [int]($state.ScrollbarWidth - 4)
                $scrollThumbRect = New-Object System.Drawing.Rectangle(
                    $thumbX,
                    [int]$scrollThumbY,
                    $thumbW,
                    [int]$state.ScrollThumbHeight
                )
                $g.FillRectangle([System.Drawing.SystemBrushes]::ControlDark, $scrollThumbRect)
            }
            else {
                $state.ScrollbarHeight = 0
                $state.ScrollbarY = 0
            }
        }
        finally {
            # Dispose GDI objects
            if ($itemFont) { $itemFont.Dispose() }
            if ($highlightBrush) { $highlightBrush.Dispose() }
            if ($selectedBrush) { $selectedBrush.Dispose() }
            if ($stringFormat) { $stringFormat.Dispose() }
            if ($stringFormatHeader) { $stringFormatHeader.Dispose() }
            if ($fontHeader) { $fontHeader.Dispose() }
        }
    })
    
    # Add mouse event handlers
    $canvas.Add_MouseDown({
        param($sender, $e)
        if ($null -eq $canvas) { return }
        $canvas.Focus()
        $mouseX = $e.X
        $mouseY = $e.Y
        $state = $script:canvasState
        
        # Check Scrollbar Click
        if ($state.MaxScroll -gt 0 -and $mouseX -ge ($canvas.Width - $state.ScrollbarWidth)) {
            if ($mouseY -ge $state.ScrollbarY -and $mouseY -le ($state.ScrollbarY + $state.ScrollbarHeight)) {
                $state.MouseDownOnScrollbar = $true
                $state.DragStartY = $mouseY - $state.ScrollbarY
            }
            else {
                $viewableHeight = $canvas.Height - $state.HeaderHeight
                if ($mouseY -lt $state.ScrollbarY) {
                    $state.ScrollOffset = [Math]::Max(0, $state.ScrollOffset - $viewableHeight)
                }
                elseif ($mouseY -gt ($state.ScrollbarY + $state.ScrollbarHeight)) {
                    $state.ScrollOffset = [Math]::Min(
                        $state.MaxScroll,
                        $state.ScrollOffset + $viewableHeight
                    )
                }
                Update-FolderListView
            }
        }
        elseif ($mouseY -gt $state.HeaderHeight) {
            $state.MouseDownOnItem = $true
            $clickedIndex = -1
            for ($i = 0; $i -lt $script:folderList.Count; $i++) {
                $item = $script:folderList[$i]
                if ($item.IsVisible -and $mouseY -ge $item.Y -and $mouseY -le ($item.Y + $state.ItemHeight)) {
                    $clickedIndex = $i
                    break
                }
            }
            
            if ($clickedIndex -ne -1) {
                $state.SelectedItemIndex = $clickedIndex
                $item = $script:folderList[$clickedIndex]
                if ($mouseX -lt $state.CheckWidth) {
                    $item.Checked = !$item.Checked
                }
                Update-FolderListView
            }
            else {
                $state.SelectedItemIndex = -1
                Update-FolderListView
            }
        }
    })
    
    $canvas.Add_MouseUp({
        param($sender, $e)
        $script:canvasState.MouseDownOnScrollbar = $false
        $script:canvasState.MouseDownOnItem = $false
    })
    
    $canvas.Add_MouseMove({
        param($sender, $e)
        if ($null -eq $canvas) { return }
        $mouseX = $e.X
        $mouseY = $e.Y
        $state = $script:canvasState
        
        # Handle Scrollbar Drag
        if ($state.MouseDownOnScrollbar) {
            $viewableHeight = $canvas.Height - $state.HeaderHeight
            $trackHeight = $viewableHeight - $state.ScrollbarHeight
            if ($trackHeight -gt 0) {
                $newThumbY = [Math]::Max(
                    $state.HeaderHeight,
                    [Math]::Min(
                        $state.HeaderHeight + $trackHeight,
                        $mouseY - $state.DragStartY
                    )
                )
                
                if ($state.MaxScroll -gt 0) {
                    $state.ScrollOffset = ($newThumbY - $state.HeaderHeight) / $trackHeight * $state.MaxScroll
                }
                else {
                    $state.ScrollOffset = 0
                }
                Update-FolderListView
            }
        }
        else {
            # Handle Hover
            $newHoverIndex = -1
            if ($mouseY -gt $state.HeaderHeight -and
                $mouseX -ge 0 -and
                $mouseX -lt ($canvas.Width - $state.ScrollbarWidth)) {
                for ($i = 0; $i -lt $script:folderList.Count; $i++) {
                    $item = $script:folderList[$i]
                    if ($item.IsVisible -and $mouseY -ge $item.Y -and $mouseY -le ($item.Y + $state.ItemHeight)) {
                        $newHoverIndex = $i
                        break
                    }
                }
            }
            
            if ($newHoverIndex -ne $state.HoveredItemIndex) {
                $state.HoveredItemIndex = $newHoverIndex
                Update-FolderListView
            }
        }
    })
    
    $canvas.Add_MouseWheel({
        param($sender, $e)
        if ($null -eq $canvas) { return }
        $state = $script:canvasState
        if ($state.MaxScroll -gt 0) {
            $scrollAmount = $e.Delta / 120 * $state.ItemHeight * 3
            $state.ScrollOffset = [Math]::Max(
                0,
                [Math]::Min(
                    $state.MaxScroll,
                    $state.ScrollOffset - $scrollAmount
                )
            )
            
            # Update hover state based on new scroll position
            $clientPoint = $canvas.PointToClient([System.Windows.Forms.Cursor]::Position)
            $mouseX = $clientPoint.X
            $mouseY = $clientPoint.Y
            $newHoverIndex = -1
            
            if ($mouseX -ge 0 -and
                $mouseX -lt ($canvas.Width - $state.ScrollbarWidth) -and
                $mouseY -ge $state.HeaderHeight -and
                $mouseY -lt $canvas.Height) {
                for ($i = 0; $i -lt $script:folderList.Count; $i++) {
                    $item = $script:folderList[$i]
                    $y = ($i * $state.ItemHeight) - $state.ScrollOffset + $state.HeaderHeight
                    if (($y + $state.ItemHeight) -gt $state.HeaderHeight -and
                        $y -lt $canvas.Height -and
                        $mouseY -ge $y -and
                        $mouseY -le ($y + $state.ItemHeight)) {
                        $newHoverIndex = $i
                        break
                    }
                }
            }
            
            if ($newHoverIndex -ne $state.HoveredItemIndex) {
                $state.HoveredItemIndex = $newHoverIndex
            }
            
            Update-FolderListView
        }
    })
    
    $canvas.Add_MouseLeave({
        if ($script:canvasState.HoveredItemIndex -ne -1) {
            $script:canvasState.HoveredItemIndex = -1
            Update-FolderListView
        }
    })
    
    $canvas.Add_Resize({
        param($sender, $e)
        Update-FolderListView
    })
    
    $script:mainForm.Controls.Add($canvas)
    $script:folderListCanvas = $canvas
}

function Show-DefaultFoldersManager {
    # Create form
    $defaultsForm = New-Object System.Windows.Forms.Form -Property @{
        Text = "Default Folder Manager (Check items to include in defaults)"
        Size = New-Object System.Drawing.Size(800, 500)
        StartPosition = "CenterParent"
        FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::SizableToolWindow
        MinimumSize = New-Object System.Drawing.Size(400, 300)
        KeyPreview = $true
    }
    
    # Panel for buttons
    $panelDefaultsButtons = New-Object System.Windows.Forms.Panel -Property @{
        Dock = [System.Windows.Forms.DockStyle]::Bottom
        Height = 50
    }
    
    # Save Button
    $btnSaveDefaults = New-Object System.Windows.Forms.Button -Property @{
        Text = "Save Defaults"
        Location = New-Object System.Drawing.Point(10, 10)
        Size = New-Object System.Drawing.Size(120, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::OK
        Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left)
    }
    
    # Cancel Button
    $btnCancelDefaults = New-Object System.Windows.Forms.Button -Property @{
        Text = "Cancel"
        Location = New-Object System.Drawing.Point(140, 10)
        Size = New-Object System.Drawing.Size(100, 30)
        DialogResult = [System.Windows.Forms.DialogResult]::Cancel
        Anchor = ([System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left)
    }
    
    $panelDefaultsButtons.Controls.AddRange(@($btnSaveDefaults, $btnCancelDefaults))
    $defaultsForm.Controls.Add($panelDefaultsButtons)
    
    # CheckedListBox for Defaults
    $chkListBoxDefaults = New-Object System.Windows.Forms.CheckedListBox -Property @{
        Dock = [System.Windows.Forms.DockStyle]::Fill
        Font = New-Object System.Drawing.Font("Segoe UI", 10)
        CheckOnClick = $true
        IntegralHeight = $false
        HorizontalScrollbar = $true
    }
    
    # Populate CheckedListBox from the current list
    foreach ($item in $script:folderList) {
        $displayPath = $item.Path
        $index = $chkListBoxDefaults.Items.Add($displayPath, $item.Default)
    }
    
    $defaultsForm.Controls.Add($chkListBoxDefaults)
    $defaultsForm.AcceptButton = $btnSaveDefaults
    $defaultsForm.CancelButton = $btnCancelDefaults
    
    # Handle Esc key
    $defaultsForm.Add_KeyDown({
        param($sender, $e)
        if ($e.KeyCode -eq [System.Windows.Forms.Keys]::Escape) {
            $defaultsForm.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
            $defaultsForm.Close()
        }
    })
    
    # Show form
    $result = $defaultsForm.ShowDialog($script:mainForm)
    
    # Process result
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $newDefaultsPaths = @()
        
        # Get checked paths
        foreach ($checkedPath in $chkListBoxDefaults.CheckedItems) {
            $newDefaultsPaths += $checkedPath
        }
        
        # Update Default property
        foreach ($item in $script:folderList) {
            if ($newDefaultsPaths -contains $item.Path) {
                $item.Default = $true
            }
            else {
                $item.Default = $false
            }
        }
        
        # Save changes
        $script:config.CustomFoldersList = $script:folderList
        $script:config.Save()
        $script:mainLogBox.AppendText("Defaults updated via manager.`r`n")
        Update-FolderListView
    }
    
    $defaultsForm.Dispose()
}

# Export module functions
Export-ModuleMember -Function Initialize-FolderListModule, Show-DefaultFoldersManager