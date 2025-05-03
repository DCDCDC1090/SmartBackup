# Compression.psm1 - Folder and file compression functionality

function Compress-Folder {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$SourcePath,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        
        [ValidateSet("Fastest", "Normal", "Maximum")]
        [string]$CompressionLevel = "Normal"
    )
    
    # Validate paths
    if (-not (Test-Path -Path $SourcePath -PathType Container)) {
        return @{
            Success = $false
            ErrorMessage = "Source path does not exist or is not a directory: $SourcePath"
            FileCount = 0
            ByteCount = 0
        }
    }
    
    # Ensure destination parent directory exists
    $destinationParent = Split-Path -Path $DestinationPath -Parent
    if (-not (Test-Path -Path $destinationParent -PathType Container)) {
        try {
            New-Item -Path $destinationParent -ItemType Directory -Force | Out-Null
        }
        catch {
            return @{
                Success = $false
                ErrorMessage = "Failed to create destination parent directory: $_"
                FileCount = 0
                ByteCount = 0
            }
        }
    }
    
    # Convert compression level string to CompressionLevel enum
    $compressionLevelEnum = switch ($CompressionLevel) {
        "Fastest" { [System.IO.Compression.CompressionLevel]::Fastest }
        "Maximum" { [System.IO.Compression.CompressionLevel]::Optimal }
        default { [System.IO.Compression.CompressionLevel]::NoCompression }
    }
    
    # Get source info
    $sourceName = Split-Path -Path $SourcePath -Leaf
    $tempZipPath = Join-Path -Path $env:TEMP -ChildPath "$sourceName-$(Get-Random).zip"
    
    # Track statistics
    $fileCount = 0
    $totalBytes = 0
    
    try {
        # Ensure System.IO.Compression.FileSystem is loaded
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        # Create zip archive
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $SourcePath, 
            $tempZipPath, 
            $compressionLevelEnum, 
            $false # Include base directory
        )
        
        # Get zip file size for statistics
        $zipFile = Get-Item -Path $tempZipPath
        $totalBytes = $zipFile.Length
        
        # Count files in source for statistics
        $fileCount = (Get-ChildItem -Path $SourcePath -Recurse -File).Count
        
        # Move the zip file to the destination
        $destinationZip = "$DestinationPath.zip"
        Move-Item -Path $tempZipPath -Destination $destinationZip -Force
        
        return @{
            Success = $true
            ZipPath = $destinationZip
            FileCount = $fileCount
            ByteCount = $totalBytes
        }
    }
    catch {
        if (Test-Path -Path $tempZipPath -PathType Leaf) {
            Remove-Item -Path $tempZipPath -Force -ErrorAction SilentlyContinue
        }
        
        return @{
            Success = $false
            ErrorMessage = "Failed to compress folder: $_"
            FileCount = 0
            ByteCount = 0
        }
    }
}

function Expand-ZipArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$ZipPath,
        
        [Parameter(Mandatory=$true)]
        [string]$DestinationPath,
        
        [switch]$OverwriteExisting
    )
    
    # Validate paths
    if (-not (Test-Path -Path $ZipPath -PathType Leaf)) {
        return @{
            Success = $false
            ErrorMessage = "Zip file does not exist: $ZipPath"
        }
    }
    
    # Ensure destination directory exists
    if (-not (Test-Path -Path $DestinationPath -PathType Container)) {
        try {
            New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
        }
        catch {
            return @{
                Success = $false
                ErrorMessage = "Failed to create destination directory: $_"
            }
        }
    }
    elseif ((Get-ChildItem -Path $DestinationPath).Count -gt 0 -and -not $OverwriteExisting) {
        return @{
            Success = $false
            ErrorMessage = "Destination directory is not empty. Use -OverwriteExisting to force extraction."
        }
    }
    
    try {
        # Ensure System.IO.Compression.FileSystem is loaded
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        # Extract the zip archive
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $DestinationPath)
        
        return @{
            Success = $true
            ExtractedPath = $DestinationPath
        }
    }
    catch {
        return @{
            Success = $false
            ErrorMessage = "Failed to extract zip archive: $_"
        }
    }
}

function Test-ZipArchive {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$ZipPath
    )
    
    # Validate path
    if (-not (Test-Path -Path $ZipPath -PathType Leaf)) {
        return @{
            Valid = $false
            ErrorMessage = "Zip file does not exist: $ZipPath"
        }
    }
    
    try {
        # Ensure System.IO.Compression.FileSystem is loaded
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        # Open the zip archive to verify it's valid
        $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        $entryCount = $zipArchive.Entries.Count
        $zipArchive.Dispose()
        
        return @{
            Valid = $true
            EntryCount = $entryCount
        }
    }
    catch {
        return @{
            Valid = $false
            ErrorMessage = "Invalid zip archive: $_"
        }
    }
}

function Get-ZipContents {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$ZipPath
    )
    
    # Validate path
    if (-not (Test-Path -Path $ZipPath -PathType Leaf)) {
        Write-Error "Zip file does not exist: $ZipPath"
        return $null
    }
    
    try {
        # Ensure System.IO.Compression.FileSystem is loaded
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        
        # Open the zip archive
        $zipArchive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        
        # Get entries
        $entries = $zipArchive.Entries | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                FullName = $_.FullName
                Size = $_.Length
                CompressedSize = $_.CompressedLength
                LastModified = $_.LastWriteTime
                IsDirectory = $_.Name -eq "" -and $_.FullName.EndsWith("/")
            }
        }
        
        # Clean up
        $zipArchive.Dispose()
        
        return $entries
    }
    catch {
        Write-Error "Failed to read zip contents: $_"
        return $null
    }
}

function Get-FolderSize {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [string]$FolderPath
    )
    
    # Validate path
    if (-not (Test-Path -Path $FolderPath -PathType Container)) {
        Write-Error "Folder does not exist: $FolderPath"
        return $null
    }
    
    try {
        $size = Get-ChildItem -Path $FolderPath -Recurse -File | Measure-Object -Property Length -Sum
        
        return [PSCustomObject]@{
            Path = $FolderPath
            Size = $size.Sum
            FileCount = $size.Count
        }
    }
    catch {
        Write-Error "Failed to calculate folder size: $_"
        return $null
    }
}

# Export module functions
Export-ModuleMember -Function Compress-Folder,
                              Expand-ZipArchive,
                              Test-ZipArchive,
                              Get-ZipContents,
                              Get-FolderSize