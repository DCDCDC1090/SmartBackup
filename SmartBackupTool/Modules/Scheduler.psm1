# Scheduler.psm1 - Task scheduling functionality

function Register-BackupTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$TaskName,
        
        [Parameter(Mandatory=$true)]
        [string]$ScriptPath,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("Daily", "Weekly", "Monthly", "Once")]
        [string]$ScheduleType,
        
        [Parameter(Mandatory=$true)]
        [DateTime]$StartTime,
        
        [string]$ProfileName = "Default",
        
        [string]$Description = "Smart Backup scheduled task",
        
        [switch]$RunAsAdmin,
        
        [PSCredential]$Credential
    )
    
    # Validate script path
    if (-not (Test-Path -Path $ScriptPath -PathType Leaf)) {
        Write-Error "Script not found: $ScriptPath"
        return $false
    }
    
    try {
        # Load the TaskScheduler com object
        $scheduler = New-Object -ComObject Schedule.Service
        $scheduler.Connect()
        
        # Get the task folder (or create it if it doesn't exist)
        $taskFolder = $null
        try {
            $taskFolder = $scheduler.GetFolder("\SmartBackupTool")
        }
        catch {
            $rootFolder = $scheduler.GetFolder("\")
            $taskFolder = $rootFolder.CreateFolder("SmartBackupTool")
        }
        
        # Check if task already exists
        $taskExists = $false
        try {
            $existingTask = $taskFolder.GetTask($TaskName)
            $taskExists = $true
            
            # Ask for confirmation before replacing
            Write-Warning "A task with the name '$TaskName' already exists."
            $confirmReplace = Read-Host "Do you want to replace it? (Y/N)"
            
            if ($confirmReplace -ne "Y" -and $confirmReplace -ne "y") {
                Write-Warning "Task creation canceled."
                return $false
            }
            
            # Delete the existing task
            $taskFolder.DeleteTask($TaskName, 0)
        }
        catch {
            # Task doesn't exist - that's fine
            $taskExists = $false
        }
        
        # Create a new task definition
        $taskDefinition = $scheduler.NewTask(0)
        
        # Set task info
        $taskDefinition.RegistrationInfo.Description = $Description
        $taskDefinition.RegistrationInfo.Author = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        
        # Set principal (run as Admin if specified)
        $logonType = 3 # Interactive logon
        $runLevel = if ($RunAsAdmin) { 1 } else { 0 } # 0 = Highest available, 1 = Highest
        
        if ($Credential) {
            $logonType = 1 # Password logon
        }
        
        $taskDefinition.Principal.LogonType = $logonType
        $taskDefinition.Principal.RunLevel = $runLevel
        
        # Add actions (run script with parameters)
        $action = $taskDefinition.Actions.Create(0) # 0 = Execute
        $action.Path = "powershell.exe"
        $action.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`" -AutoRun -ProfileName `"$ProfileName`""
        
        # Set settings
        $taskDefinition.Settings.Enabled = $true
        $taskDefinition.Settings.Hidden = $false
        $taskDefinition.Settings.AllowDemandStart = $true
        $taskDefinition.Settings.DisallowStartIfOnBatteries = $false
        $taskDefinition.Settings.StopIfGoingOnBatteries = $false
        $taskDefinition.Settings.MultipleInstances = 1 # IgnoreNew
        $taskDefinition.Settings.RestartInterval = "PT5M" # 5 minutes
        $taskDefinition.Settings.RestartCount = 3
        
        # Set trigger based on schedule type
        $trigger = $null
        switch ($ScheduleType) {
            "Daily" {
                $trigger = $taskDefinition.Triggers.Create(2) # 2 = Daily
                $trigger.DaysInterval = 1 # Every day
            }
            "Weekly" {
                $trigger = $taskDefinition.Triggers.Create(3) # 3 = Weekly
                $trigger.DaysOfWeek = 1 # Sunday (1 = Sunday, 2 = Monday, 4 = Tuesday, etc.)
                $trigger.WeeksInterval = 1 # Every week
            }
            "Monthly" {
                $trigger = $taskDefinition.Triggers.Create(4) # 4 = Monthly
                $trigger.DaysOfMonth = 1 # First day of the month
                $trigger.MonthsOfYear = 4095 # All months (2^12 - 1)
            }
            "Once" {
                $trigger = $taskDefinition.Triggers.Create(1) # 1 = Once
            }
        }
        
        # Set trigger start time
        $trigger.StartBoundary = $StartTime.ToString("yyyy-MM-ddTHH:mm:ss")
        $trigger.Enabled = $true
        
        # Create the task
        if ($Credential) {
            $taskFolder.RegisterTaskDefinition(
                $TaskName,
                $taskDefinition,
                6, # Create or update
                $Credential.UserName,
                $Credential.GetNetworkCredential().Password,
                $logonType,
                $null
            )
        }
        else {
            $taskFolder.RegisterTaskDefinition(
                $TaskName,
                $taskDefinition,
                6, # Create or update
                $null,
                $null,
                $logonType
            )
        }
        
        Write-Host "Task '$TaskName' has been scheduled successfully."
        return $true
    }
    catch {
        Write-Error "Failed to create scheduled task: $_"
        return $false
    }
}

function Get-BackupTasks {
    [CmdletBinding()]
    param ()
    
    try {
        # Load the TaskScheduler com object
        $scheduler = New-Object -ComObject Schedule.Service
        $scheduler.Connect()
        
        $taskFolder = $null
        try {
            $taskFolder = $scheduler.GetFolder("\SmartBackupTool")
        }
        catch {
            Write-Warning "No SmartBackupTool folder found in Task Scheduler."
            return @()
        }
        
        $tasks = @()
        $taskFolder.GetTasks(0) | ForEach-Object {
            # Parse arguments to extract ProfileName
            $profileName = "Default"
            if ($_.Actions.Item(1) -and $_.Actions.Item(1).Arguments -match "-ProfileName\s+`"([^`"]+)`"") {
                $profileName = $matches[1]
            }
            
            # Get next run time
            $nextRunTime = "Not scheduled"
            if ($_.NextRunTime) {
                $nextRunTime = Get-Date $_.NextRunTime -Format "yyyy-MM-dd HH:mm:ss"
            }
            
            # Get last run time and result
            $lastRunTime = "Never"
            $lastRunResult = "Unknown"
            if ($_.LastRunTime) {
                $lastRunTime = Get-Date $_.LastRunTime -Format "yyyy-MM-dd HH:mm:ss"
                switch ($_.LastTaskResult) {
                    0 { $lastRunResult = "Success" }
                    1 { $lastRunResult = "Function incorrect" }
                    2 { $lastRunResult = "File not found" }
                    10 { $lastRunResult = "Environment incorrect" }
                    default { $lastRunResult = "Error (Code: $($_.LastTaskResult))" }
                }
            }
            
            $tasks += [PSCustomObject]@{
                Name = $_.Name
                Path = $_.Path
                State = $(switch ($_.State) {
                    1 { "Disabled" }
                    2 { "Queued" }
                    3 { "Ready" }
                    4 { "Running" }
                    default { "Unknown" }
                })
                Enabled = $_.Enabled
                LastRunTime = $lastRunTime
                LastResult = $lastRunResult
                NextRunTime = $nextRunTime
                ProfileName = $profileName
                Author = $_.Definition.RegistrationInfo.Author
                Description = $_.Definition.RegistrationInfo.Description
            }
        }
        
        return $tasks
    }
    catch {
        Write-Error "Failed to retrieve scheduled tasks: $_"
        return @()
    }
}

function Remove-BackupTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$TaskName
    )
    
    try {
        # Load the TaskScheduler com object
        $scheduler = New-Object -ComObject Schedule.Service
        $scheduler.Connect()
        
        $taskFolder = $null
        try {
            $taskFolder = $scheduler.GetFolder("\SmartBackupTool")
        }
        catch {
            Write-Error "SmartBackupTool task folder not found."
            return $false
        }
        
        # Check if task exists
        try {
            $taskFolder.GetTask($TaskName) | Out-Null
        }
        catch {
            Write-Error "Task '$TaskName' not found."
            return $false
        }
        
        # Delete the task
        $taskFolder.DeleteTask($TaskName, 0)
        Write-Host "Task '$TaskName' has been removed successfully."
        return $true
    }
    catch {
        Write-Error "Failed to remove scheduled task: $_"
        return $false
    }
}

function Update-BackupTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$TaskName,
        
        [ValidateSet("Daily", "Weekly", "Monthly", "Once")]
        [string]$ScheduleType,
        
        [DateTime]$StartTime,
        
        [string]$ProfileName,
        
        [string]$Description,
        
        [switch]$Enable,
        
        [switch]$Disable
    )
    
    try {
        # Load the TaskScheduler com object
        $scheduler = New-Object -ComObject Schedule.Service
        $scheduler.Connect()
        
        $taskFolder = $null
        try {
            $taskFolder = $scheduler.GetFolder("\SmartBackupTool")
        }
        catch {
            Write-Error "SmartBackupTool task folder not found."
            return $false
        }
        
        # Get existing task
        $existingTask = $null
        try {
            $existingTask = $taskFolder.GetTask($TaskName)
        }
        catch {
            Write-Error "Task '$TaskName' not found."
            return $false
        }
        
        # Get the task definition for editing
        $taskDefinition = $existingTask.Definition
        
        # Update fields if provided
        if ($Description) {
            $taskDefinition.RegistrationInfo.Description = $Description
        }
        
        if ($ProfileName) {
            # Update the action to use the new profile
            $action = $taskDefinition.Actions.Item(1)
            $newArgs = $action.Arguments -replace "-ProfileName\s+`"[^`"]+`"", "-ProfileName `"$ProfileName`""
            $action.Arguments = $newArgs
        }
        
        # Enable or disable the task
        if ($Enable) {
            $taskDefinition.Settings.Enabled = $true
        }
        elseif ($Disable) {
            $taskDefinition.Settings.Enabled = $false
        }
        
        # Update schedule if specified
        if ($ScheduleType -or $StartTime) {
            # Get the first trigger
            $trigger = $taskDefinition.Triggers.Item(1)
            
            # Update trigger type if specified
            if ($ScheduleType) {
                # We need to create a new trigger of the right type
                $taskDefinition.Triggers.Remove(1)
                $triggerType = switch ($ScheduleType) {
                    "Daily" { 2 }
                    "Weekly" { 3 }
                    "Monthly" { 4 }
                    "Once" { 1 }
                }
                $newTrigger = $taskDefinition.Triggers.Create($triggerType)
                
                # Set up the specific schedule parameters
                switch ($ScheduleType) {
                    "Daily" {
                        $newTrigger.DaysInterval = 1
                    }
                    "Weekly" {
                        $newTrigger.DaysOfWeek = 1
                        $newTrigger.WeeksInterval = 1
                    }
                    "Monthly" {
                        $newTrigger.DaysOfMonth = 1
                        $newTrigger.MonthsOfYear = 4095
                    }
                }
                
                # Use the existing start time if not provided
                if (-not $StartTime) {
                    # Parse the existing start time
                    if ($trigger.StartBoundary -match "(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})") {
                        $newTrigger.StartBoundary = $matches[1]
                    }
                    else {
                        $newTrigger.StartBoundary = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
                    }
                }
                else {
                    $newTrigger.StartBoundary = $StartTime.ToString("yyyy-MM-ddTHH:mm:ss")
                }
                
                $newTrigger.Enabled = $true
            }
            elseif ($StartTime) {
                # Just update the start time of the existing trigger
                $trigger.StartBoundary = $StartTime.ToString("yyyy-MM-ddTHH:mm:ss")
            }
        }
        
        # Register the updated task
        $taskFolder.RegisterTaskDefinition(
            $TaskName,
            $taskDefinition,
            6, # Create or update
            $null,
            $null,
            $taskDefinition.Principal.LogonType
        )
        
        Write-Host "Task '$TaskName' has been updated successfully."
        return $true
    }
    catch {
        Write-Error "Failed to update scheduled task: $_"
        return $false
    }
}

function Run-BackupTask {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$TaskName
    )
    
    try {
        # Load the TaskScheduler com object
        $scheduler = New-Object -ComObject Schedule.Service
        $scheduler.Connect()
        
        $taskFolder = $null
        try {
            $taskFolder = $scheduler.GetFolder("\SmartBackupTool")
        }
        catch {
            Write-Error "SmartBackupTool task folder not found."
            return $false
        }
        
        # Get the task
        $task = $null
        try {
            $task = $taskFolder.GetTask($TaskName)
        }
        catch {
            Write-Error "Task '$TaskName' not found."
            return $false
        }
        
        # Run the task
        $task.Run(0) | Out-Null
        Write-Host "Task '$TaskName' has been started."
        return $true
    }
    catch {
        Write-Error "Failed to run scheduled task: $_"
        return $false
    }
}

# Helper function to check if running as administrator
function Test-Administrator {
    $currentUser = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    $currentUser.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

# Export module functions
Export-ModuleMember -Function Register-BackupTask, 
                              Get-BackupTasks, 
                              Remove-BackupTask, 
                              Update-BackupTask, 
                              Run-BackupTask,
                              Test-Administrator