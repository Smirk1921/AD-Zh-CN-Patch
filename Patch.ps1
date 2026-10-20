[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("Install", "Uninstall", "Check")]
    [string]$Action = "Install",

    [string]$GameRoot,

    [string[]]$SteamRoot,

    [switch]$Interactive,

    [switch]$Elevated
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

# This installer deliberately uses only Windows PowerShell and the .NET Base
# Class Library. Friends receiving the patch do not need Node.js, an ASAR tool,
# a network connection, or a copy of the original game archive in the patch.

$Script:ScriptPath = [IO.Path]::GetFullPath($MyInvocation.MyCommand.Path)
$Script:PatchDirectory = Split-Path -Parent $Script:ScriptPath
$Script:ManifestPath = Join-Path $Script:PatchDirectory "patch-manifest.json"
$Script:StateDirectory = Join-Path $env:LOCALAPPDATA "AntimatterDimensionsZhPatch"
$Script:StatePath = Join-Path $Script:StateDirectory "state.json"
$Script:AdditionalSteamRoots = @($SteamRoot)
# Bump both lines together with patch-manifest.json whenever the payload changes.
# SupportedManifestVersion is the version this script ships with; the upgrade
# list is every earlier released version whose install can be rebuilt safely.
$Script:SupportedManifestVersion = "0.3.5"
$Script:CompatibleUpgradeVersions = @("0.1.0", "0.1.1", "0.2.0", "0.2.1", "0.2.2", "0.2.3", "0.2.4", "0.2.5", "0.2.6", "0.2.7", "0.2.8", "0.2.9", "0.3.0", "0.3.1", "0.3.2", "0.3.3", "0.3.4")

function Write-Step {
    param([string]$Message)
    Write-Host "[AD Zh-CN] $Message"
}

function Write-Failure {
    param([string]$Message)
    Write-Host "[AD Zh-CN] ERROR: $Message" -ForegroundColor Red
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    # Get-FileHash is a module function in Windows PowerShell 5.1. When this
    # batch file is launched from another PowerShell edition, an inherited
    # PSModulePath can shadow that built-in module with an incompatible copy.
    # Hash directly through .NET so the distributable has no module dependency.
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace("-", "")
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Get-BytesSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace("-", "")
    }
    finally {
        $algorithm.Dispose()
    }
}

function Read-Utf8TextFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    # Windows PowerShell 5.1 treats UTF-8 without a BOM as the active ANSI
    # code page when Get-Content has no explicit encoding. Patch state and
    # Steam metadata may contain non-ASCII library paths, so decode them with
    # strict UTF-8 semantics on every supported Windows locale.
    $encoding = New-Object Text.UTF8Encoding($false, $true)
    return [IO.File]::ReadAllText($Path, $encoding)
}

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file was not found: $Path"
    }
    return (Read-Utf8TextFile -Path $Path) | ConvertFrom-Json
}

function Write-JsonFileAtomic {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporary = Join-Path $directory (".{0}.{1}.tmp" -f (Split-Path -Leaf $Path), [Guid]::NewGuid().ToString("N"))
    try {
        $json = $Value | ConvertTo-Json -Depth 20
        [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            $rollback = Join-Path $directory (".state-rollback-{0}.json" -f [Guid]::NewGuid().ToString("N"))
            [IO.File]::Replace($temporary, $Path, $rollback, $true)
            if (Test-Path -LiteralPath $rollback -PathType Leaf) {
                Remove-Item -LiteralPath $rollback -Force
            }
        }
        else {
            [IO.File]::Move($temporary, $Path)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) {
            Remove-Item -LiteralPath $temporary -Force
        }
    }
}

function Get-ExistingState {
    if (-not (Test-Path -LiteralPath $Script:StatePath -PathType Leaf)) {
        return $null
    }
    try {
        return Read-JsonFile -Path $Script:StatePath
    }
    catch {
        throw "Patch state is unreadable at $Script:StatePath. Refusing to guess: $($_.Exception.Message)"
    }
}

function Get-NormalizedFullPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    $root = [IO.Path]::GetPathRoot($full)
    if ($full.Length -gt $root.Length) {
        $full = $full.TrimEnd([char[]]@('\', '/'))
    }
    return $full
}

function Test-SamePath {
    param(
        [string]$Left,
        [string]$Right
    )
    if ([string]::IsNullOrWhiteSpace($Left) -or [string]::IsNullOrWhiteSpace($Right)) { return $false }
    try {
        return [string]::Equals(
            (Get-NormalizedFullPath -Path $Left),
            (Get-NormalizedFullPath -Path $Right),
            [StringComparison]::OrdinalIgnoreCase
        )
    }
    catch { return $false }
}

function Add-CandidatePath {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[string]]$List,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    try {
        $full = Get-NormalizedFullPath -Path $Path
    }
    catch { return }
    foreach ($existing in $List) {
        if ([string]::Equals($existing, $full, [StringComparison]::OrdinalIgnoreCase)) { return }
    }
    $List.Add($full)
}

function Get-SteamRoots {
    $roots = New-Object "Collections.Generic.List[string]"
    # A portable Steam installation may not appear in the registry. This
    # optional input is authoritative so a user can constrain discovery to the
    # Steam installation they dragged or supplied, without another registered
    # Steam copy being selected behind their back.
    foreach ($additionalRoot in $Script:AdditionalSteamRoots) {
        Add-CandidatePath -List $roots -Path $additionalRoot
    }
    if ($roots.Count -gt 0) { return $roots }
    $registryLocations = @(
        @{ Path = "HKCU:\Software\Valve\Steam"; Name = "SteamPath" },
        @{ Path = "HKLM:\Software\WOW6432Node\Valve\Steam"; Name = "InstallPath" },
        @{ Path = "HKLM:\Software\Valve\Steam"; Name = "InstallPath" }
    )
    foreach ($location in $registryLocations) {
        try {
            $value = (Get-ItemProperty -LiteralPath $location.Path -ErrorAction Stop).($location.Name)
            Add-CandidatePath -List $roots -Path $value
        }
        catch { }
    }
    # Some stripped-down Windows environments do not expose both Program Files
    # variables. Avoid turning an optional fallback into an installer failure.
    if (${env:ProgramFiles(x86)}) {
        Add-CandidatePath -List $roots -Path (Join-Path ${env:ProgramFiles(x86)} "Steam")
    }
    if ($env:ProgramFiles) {
        Add-CandidatePath -List $roots -Path (Join-Path $env:ProgramFiles "Steam")
    }
    return $roots
}

function Get-SteamLibraryRoots {
    param([Parameter(Mandatory = $true)][string]$SteamRoot)
    $libraries = New-Object "Collections.Generic.List[string]"
    Add-CandidatePath -List $libraries -Path $SteamRoot
    $vdf = Join-Path $SteamRoot "steamapps\libraryfolders.vdf"
    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        $text = Read-Utf8TextFile -Path $vdf
        foreach ($match in [regex]::Matches($text, '"path"\s+"([^"]+)"', [Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            Add-CandidatePath -List $libraries -Path ($match.Groups[1].Value -replace '\\\\', '\')
        }
    }
    return $libraries
}

function Read-SteamAppManifest {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $text = Read-Utf8TextFile -Path $Path
    $appId = [regex]::Match($text, '"appid"\s+"([0-9]+)"').Groups[1].Value
    $buildId = [regex]::Match($text, '"buildid"\s+"([0-9]+)"').Groups[1].Value
    $installDir = [regex]::Match($text, '"installdir"\s+"([^"]+)"').Groups[1].Value
    return [pscustomobject]@{
        Path = $Path
        AppId = $appId
        BuildId = $buildId
        InstallDir = $installDir
    }
}

function Get-AppManifestForGameRoot {
    param([Parameter(Mandatory = $true)][string]$ResolvedGameRoot)
    $commonDirectory = Split-Path -Parent $ResolvedGameRoot
    $steamAppsDirectory = Split-Path -Parent $commonDirectory
    return Read-SteamAppManifest -Path (Join-Path $steamAppsDirectory "appmanifest_1399720.acf")
}

function Test-GameRootShape {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        return $false
    }
    return (Test-Path -LiteralPath (Join-Path $Path "Antimatter Dimensions.exe") -PathType Leaf) -and
        (Test-Path -LiteralPath (Join-Path $Path "resources\app.asar") -PathType Leaf)
}

function Add-ManifestGameRoot {
    param(
        [Parameter(Mandatory = $true)][object]$List,
        [Parameter(Mandatory = $true)][string]$SteamAppsDirectory
    )
    $manifest = Read-SteamAppManifest -Path (Join-Path $SteamAppsDirectory "appmanifest_1399720.acf")
    if (-not $manifest -or $manifest.AppId -ne "1399720" -or -not $manifest.InstallDir) { return }
    Add-CandidatePath -List $List -Path (Join-Path $SteamAppsDirectory ("common\{0}" -f $manifest.InstallDir))
}

function Get-ExplicitGameRoots {
    param([Parameter(Mandatory = $true)][string]$Path)

    # Drag-and-drop may provide the game folder, its executable, resources,
    # app.asar, a Steam library root, or its steamapps/common directory. Only
    # deterministic relatives of that explicit input are considered; this
    # function never falls back to a different library after a bad selection.
    $cleanPath = $Path.Trim().Trim([char]'"')
    $candidates = New-Object "Collections.Generic.List[string]"
    try { $full = [IO.Path]::GetFullPath($cleanPath) } catch { return @() }

    if (Test-Path -LiteralPath $full -PathType Leaf) {
        $leafName = Split-Path -Leaf $full
        if ([string]::Equals($leafName, "Antimatter Dimensions.exe", [StringComparison]::OrdinalIgnoreCase)) {
            Add-CandidatePath -List $candidates -Path (Split-Path -Parent $full)
        }
        elseif ([string]::Equals($leafName, "app.asar", [StringComparison]::OrdinalIgnoreCase)) {
            $parent = Split-Path -Parent $full
            if ([string]::Equals((Split-Path -Leaf $parent), "resources", [StringComparison]::OrdinalIgnoreCase)) {
                Add-CandidatePath -List $candidates -Path (Split-Path -Parent $parent)
            }
        }
        elseif ([string]::Equals($leafName, "appmanifest_1399720.acf", [StringComparison]::OrdinalIgnoreCase)) {
            Add-ManifestGameRoot -List $candidates -SteamAppsDirectory (Split-Path -Parent $full)
        }
    }
    elseif (Test-Path -LiteralPath $full -PathType Container) {
        Add-CandidatePath -List $candidates -Path $full
        $leafName = Split-Path -Leaf $full
        if ([string]::Equals($leafName, "resources", [StringComparison]::OrdinalIgnoreCase)) {
            Add-CandidatePath -List $candidates -Path (Split-Path -Parent $full)
        }
        Add-ManifestGameRoot -List $candidates -SteamAppsDirectory $full
        foreach ($library in Get-SteamLibraryRoots -SteamRoot $full) {
            Add-ManifestGameRoot -List $candidates -SteamAppsDirectory (Join-Path $library "steamapps")
        }
        if ([string]::Equals($leafName, "common", [StringComparison]::OrdinalIgnoreCase)) {
            Add-ManifestGameRoot -List $candidates -SteamAppsDirectory (Split-Path -Parent $full)
        }
    }

    return @($candidates | Where-Object { Test-GameRootShape -Path $_ })
}

function Select-GameInstallationFolder {
    param([string[]]$SuggestedRoots = @())

    try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop }
    catch {
        throw "The game directory could not be selected automatically. Drag the game folder onto Install-Chinese.cmd or run Patch.ps1 with -GameRoot."
    }

    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = "Select the Antimatter Dimensions game folder (the folder containing Antimatter Dimensions.exe)."
    $dialog.ShowNewFolderButton = $false
    if ($SuggestedRoots.Count -gt 0 -and (Test-Path -LiteralPath $SuggestedRoots[0] -PathType Container)) {
        $dialog.SelectedPath = $SuggestedRoots[0]
    }
    try {
        while ($true) {
            if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) {
                throw "Game directory selection was cancelled; no files were changed."
            }
            $selected = @(Get-ExplicitGameRoots -Path $dialog.SelectedPath)
            if ($selected.Count -eq 1) { return $selected[0] }
            [void][Windows.Forms.MessageBox]::Show(
                "That folder is not a Steam installation of Antimatter Dimensions. Select the folder containing Antimatter Dimensions.exe.",
                "Antimatter Dimensions Chinese Patch",
                [Windows.Forms.MessageBoxButtons]::OK,
                [Windows.Forms.MessageBoxIcon]::Warning
            )
        }
    }
    finally {
        $dialog.Dispose()
    }
}

function Resolve-GameInstallation {
    param(
        [string]$RequestedRoot,
        [object]$State,
        [switch]$AllowInteractiveSelection
    )
    # An explicit path is an instruction, not merely another candidate. Never
    # silently fall back to a different Steam library after a typing mistake.
    if ($RequestedRoot) {
        $requestedCandidates = @(Get-ExplicitGameRoots -Path $RequestedRoot)
        if ($requestedCandidates.Count -eq 1) { return $requestedCandidates[0] }
        if ($requestedCandidates.Count -gt 1 -and $AllowInteractiveSelection) {
            return Select-GameInstallationFolder -SuggestedRoots $requestedCandidates
        }
        if ($requestedCandidates.Count -gt 1) {
            throw "The requested path contains multiple game installations. Specify the intended game directory."
        }
        throw "The requested path does not identify an Antimatter Dimensions installation: $RequestedRoot"
    }

    $candidates = New-Object "Collections.Generic.List[string]"
    $hasRequestedSteamRoots = @($Script:AdditionalSteamRoots | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_)
    }).Count -gt 0
    if (-not $hasRequestedSteamRoots) {
        if ($State -and $State.gameRoot) { Add-CandidatePath -List $candidates -Path ([string]$State.gameRoot) }

        # These two locations make the patch convenient when it is extracted
        # into the game root or one of its direct child folders. They are not
        # used when -SteamRoot explicitly constrains the discovery scope.
        Add-CandidatePath -List $candidates -Path $Script:PatchDirectory
        Add-CandidatePath -List $candidates -Path (Split-Path -Parent $Script:PatchDirectory)
    }

    foreach ($steamRoot in Get-SteamRoots) {
        if (-not (Test-Path -LiteralPath $steamRoot -PathType Container)) { continue }
        foreach ($library in Get-SteamLibraryRoots -SteamRoot $steamRoot) {
            $manifestPath = Join-Path $library "steamapps\appmanifest_1399720.acf"
            $appManifest = Read-SteamAppManifest -Path $manifestPath
            if (-not $appManifest -or -not $appManifest.InstallDir) { continue }
            Add-CandidatePath -List $candidates -Path (Join-Path $library ("steamapps\common\{0}" -f $appManifest.InstallDir))
        }
    }

    $valid = @($candidates | Where-Object { Test-GameRootShape -Path $_ })
    if ($valid.Count -eq 0) {
        if ($AllowInteractiveSelection) { return Select-GameInstallationFolder }
        if ($hasRequestedSteamRoots) {
            throw "Antimatter Dimensions was not found under the specified Steam root."
        }
        throw "Antimatter Dimensions was not found. Run Patch.ps1 with -GameRoot followed by the game directory."
    }
    if ($valid.Count -eq 1) { return $valid[0] }

    # A single state file owns one installation. Never infer intent from an
    # archive hash when more than one real copy exists: a valid original may be
    # the user's untouched backup copy rather than the intended target.
    if ($AllowInteractiveSelection) { return Select-GameInstallationFolder -SuggestedRoots $valid }
    throw "Multiple game installations were found. Specify the intended one with -GameRoot."
}

function Read-AsarHeader {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = New-Object IO.BinaryReader($stream, (New-Object Text.UTF8Encoding($false)), $true)
    try {
        if ($stream.Length -lt 16) { throw "ASAR is too small to contain a valid header." }
        $pickleLength = $reader.ReadUInt32()
        $headerPayloadLength = $reader.ReadUInt32()
        $stringPayloadLength = $reader.ReadUInt32()
        $jsonLength = $reader.ReadUInt32()
        if ($pickleLength -ne 4 -or $jsonLength -lt 2 -or $jsonLength -gt 104857600) {
            throw "ASAR header fields are invalid."
        }
        $paddedJsonLength = [int](($jsonLength + 3) -band -4)
        $dataOffset = 16L + $paddedJsonLength
        if ($headerPayloadLength -ne (8 + $paddedJsonLength) -or
            $stringPayloadLength -ne (4 + $paddedJsonLength) -or $dataOffset -gt $stream.Length) {
            throw "ASAR pickle lengths are inconsistent."
        }
        $jsonBytes = $reader.ReadBytes([int]$jsonLength)
        if ($jsonBytes.Length -ne $jsonLength) { throw "ASAR header is truncated." }
        $json = (New-Object Text.UTF8Encoding($false)).GetString($jsonBytes)
        return [pscustomobject]@{
            Tree = $json | ConvertFrom-Json
            DataOffset = $dataOffset
            JsonLength = [int]$jsonLength
            ArchiveLength = $stream.Length
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-AsarEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Tree,
        [Parameter(Mandatory = $true)][string]$ArchivePath
    )
    $parts = @(@($ArchivePath -split '[\\/]') | Where-Object { $_ })
    $files = $Tree.files
    for ($index = 0; $index -lt $parts.Count; $index += 1) {
        $property = $files.PSObject.Properties[$parts[$index]]
        if (-not $property) { return $null }
        $entry = $property.Value
        if ($index -eq $parts.Count - 1) { return $entry }
        # Under StrictMode, directly reading a missing property throws instead
        # of returning null. Treat a leaf encountered mid-path as "not found".
        $childFiles = $entry.PSObject.Properties["files"]
        if (-not $childFiles) { return $null }
        $files = $childFiles.Value
    }
    return $null
}

function Set-AsarEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Tree,
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][object]$Entry
    )
    $parts = @(@($ArchivePath -split '[\\/]') | Where-Object { $_ })
    $files = $Tree.files
    for ($index = 0; $index -lt $parts.Count - 1; $index += 1) {
        $property = $files.PSObject.Properties[$parts[$index]]
        if (-not $property) {
            $directoryEntry = [pscustomobject]@{ files = [pscustomobject]@{} }
            $files | Add-Member -MemberType NoteProperty -Name $parts[$index] -Value $directoryEntry
            $property = $files.PSObject.Properties[$parts[$index]]
        }
        $childFiles = $property.Value.PSObject.Properties["files"]
        if (-not $childFiles) {
            throw "ASAR path collides with a file while adding $ArchivePath"
        }
        $files = $childFiles.Value
    }
    $leaf = $parts[$parts.Count - 1]
    $existing = $files.PSObject.Properties[$leaf]
    if ($existing) {
        $existing.Value = $Entry
    }
    else {
        $files | Add-Member -MemberType NoteProperty -Name $leaf -Value $Entry
    }
}

function Read-AsarFileBytes {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][object]$Header,
        [Parameter(Mandatory = $true)][string]$InternalPath
    )
    $entry = Get-AsarEntry -Tree $Header.Tree -ArchivePath $InternalPath
    if (-not $entry) { throw "Packed ASAR file was not found: $InternalPath" }
    $unpackedProperty = $entry.PSObject.Properties["unpacked"]
    $offsetProperty = $entry.PSObject.Properties["offset"]
    $sizeProperty = $entry.PSObject.Properties["size"]
    if (($unpackedProperty -and [bool]$unpackedProperty.Value) -or -not $offsetProperty -or -not $sizeProperty) {
        throw "Packed ASAR file was not found: $InternalPath"
    }
    $size = [int64]$sizeProperty.Value
    if ($size -gt [int]::MaxValue) { throw "ASAR entry is too large to read: $InternalPath" }
    $stream = [IO.File]::Open($ArchivePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $stream.Position = [int64]$Header.DataOffset + [int64]([string]$offsetProperty.Value)
        $bytes = New-Object byte[] ([int]$size)
        $read = 0
        while ($read -lt $bytes.Length) {
            $count = $stream.Read($bytes, $read, $bytes.Length - $read)
            if ($count -le 0) { throw "ASAR entry is truncated: $InternalPath" }
            $read += $count
        }
        # The unary comma keeps PowerShell from expanding every byte onto the
        # pipeline, which is essential for the bundled 25 MB font payload.
        return ,$bytes
    }
    finally {
        $stream.Dispose()
    }
}

function Get-GameVersionFromAsar {
    param([Parameter(Mandatory = $true)][string]$AsarPath)
    $header = Read-AsarHeader -Path $AsarPath
    $bytes = Read-AsarFileBytes -ArchivePath $AsarPath -Header $header -InternalPath "AppFiles/version.txt"
    $text = (New-Object Text.UTF8Encoding($false)).GetString($bytes)
    return ($text | ConvertFrom-Json).version.ToString([Globalization.CultureInfo]::InvariantCulture)
}

function Assert-PayloadIntegrity {
    foreach ($payload in $Script:Manifest.payload) {
        $source = Join-Path $Script:PatchDirectory ([string]$payload.source)
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Patch payload is missing: $source"
        }
        $actual = Get-Sha256 -Path $source
        if ($actual -ne ([string]$payload.sha256).ToUpperInvariant()) {
            throw "Patch payload failed SHA-256 verification: $($payload.source)"
        }
    }
}

function Build-PatchedIndex {
    param([Parameter(Mandatory = $true)][byte[]]$OriginalBytes)
    $encoding = New-Object Text.UTF8Encoding($false)
    $html = $encoding.GetString($OriginalBytes)
    if ($html.Contains([string]$Script:Manifest.indexMarker)) {
        throw "The source index already contains this patch marker."
    }
    if (-not $html.Contains('<html lang="en">') -or -not $html.Contains('<title>Antimatter Dimensions</title>')) {
        throw "The source index layout is not the supported build."
    }
    $html = $html.Replace('<html lang="en">', '<html lang="zh-CN">')
    # Keep this source file ASCII so Windows PowerShell 5.1 can parse it on
    # every system locale. The UTF-8 runtime sets the visible Chinese title.
    $html = $html.Replace('<title>Antimatter Dimensions</title>', '<title>Antimatter Dimensions (Zh-CN)</title>')
    $styleTag = '  <link rel="stylesheet" type="text/css" href="stylesheets/zh-cn.css">' + "`n"
    $html = $html.Replace('</head>', $styleTag + '</head>')
    $scriptAnchor = '<script defer src="js/app.js"></script>'
    if (-not $html.Contains($scriptAnchor)) { throw "The game script anchor was not found in index.html." }
    $injection = $scriptAnchor + "`n" +
        '  <!-- ' + [string]$Script:Manifest.indexMarker + ' -->' + "`n" +
        '  <script defer src="js/zh-cn-catalog.js"></script>' + "`n" +
        '  <script defer src="js/zh-cn-runtime.js"></script>'
    $html = $html.Replace($scriptAnchor, $injection)
    return ,$encoding.GetBytes($html)
}

function Copy-StreamRange {
    param(
        [Parameter(Mandatory = $true)][IO.Stream]$SourceStream,
        [Parameter(Mandatory = $true)][IO.Stream]$DestinationStream,
        [Parameter(Mandatory = $true)][int64]$Count
    )
    $buffer = New-Object byte[] 1048576
    $remaining = $Count
    while ($remaining -gt 0) {
        $wanted = [int][Math]::Min($buffer.Length, $remaining)
        $read = $SourceStream.Read($buffer, 0, $wanted)
        if ($read -le 0) { throw "Unexpected end of ASAR data while copying." }
        $DestinationStream.Write($buffer, 0, $read)
        $remaining -= $read
    }
}

function Build-PatchedAsar {
    param(
        [Parameter(Mandatory = $true)][string]$OriginalPath,
        [Parameter(Mandatory = $true)][string]$OutputPath
    )
    Assert-PayloadIntegrity
    $header = Read-AsarHeader -Path $OriginalPath
    $originalDataLength = [int64]$header.ArchiveLength - [int64]$header.DataOffset
    $indexBytes = Read-AsarFileBytes -ArchivePath $OriginalPath -Header $header -InternalPath "AppFiles/index.html"
    $patchedIndex = Build-PatchedIndex -OriginalBytes $indexBytes

    $appendItems = New-Object Collections.ArrayList
    [void]$appendItems.Add([pscustomobject]@{
        ArchivePath = "AppFiles/index.html"
        Bytes = $patchedIndex
    })
    foreach ($payload in $Script:Manifest.payload) {
        $source = Join-Path $Script:PatchDirectory ([string]$payload.source)
        [void]$appendItems.Add([pscustomobject]@{
            ArchivePath = [string]$payload.archivePath
            Bytes = [IO.File]::ReadAllBytes($source)
        })
    }

    $nextOffset = $originalDataLength
    foreach ($item in $appendItems) {
        $entry = [pscustomobject]@{
            size = [int64]$item.Bytes.LongLength
            offset = $nextOffset.ToString([Globalization.CultureInfo]::InvariantCulture)
        }
        Set-AsarEntry -Tree $header.Tree -ArchivePath $item.ArchivePath -Entry $entry
        $nextOffset += [int64]$item.Bytes.LongLength
    }

    $headerJson = $header.Tree | ConvertTo-Json -Depth 100 -Compress
    $encoding = New-Object Text.UTF8Encoding($false)
    $headerBytes = $encoding.GetBytes($headerJson)
    $paddedLength = [int](($headerBytes.Length + 3) -band -4)

    $input = [IO.File]::Open($OriginalPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $output = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $writer = New-Object IO.BinaryWriter($output, $encoding, $true)
    try {
        $writer.Write([uint32]4)
        $writer.Write([uint32](8 + $paddedLength))
        $writer.Write([uint32](4 + $paddedLength))
        $writer.Write([uint32]$headerBytes.Length)
        $writer.Write($headerBytes)
        if ($paddedLength -gt $headerBytes.Length) {
            $writer.Write((New-Object byte[] ($paddedLength - $headerBytes.Length)))
        }
        $writer.Flush()

        $input.Position = [int64]$header.DataOffset
        Copy-StreamRange -SourceStream $input -DestinationStream $output -Count $originalDataLength
        foreach ($item in $appendItems) {
            $output.Write($item.Bytes, 0, $item.Bytes.Length)
        }
        $output.Flush()
    }
    finally {
        $writer.Dispose()
        $output.Dispose()
        $input.Dispose()
    }
}

function Assert-PatchedAsar {
    param([Parameter(Mandatory = $true)][string]$Path)
    $header = Read-AsarHeader -Path $Path
    foreach ($required in @("package.json", "main.js", "AppFiles/index.html", "AppFiles/js/app.js")) {
        if (-not (Get-AsarEntry -Tree $header.Tree -ArchivePath $required)) {
            throw "Generated ASAR is missing required game file: $required"
        }
    }
    foreach ($payload in $Script:Manifest.payload) {
        $entry = Get-AsarEntry -Tree $header.Tree -ArchivePath ([string]$payload.archivePath)
        if (-not $entry -or [int64]$entry.size -ne [int64]$payload.size) {
            throw "Generated ASAR has an invalid payload entry: $($payload.archivePath)"
        }
        $payloadBytes = Read-AsarFileBytes -ArchivePath $Path -Header $header -InternalPath ([string]$payload.archivePath)
        if ((Get-BytesSha256 -Bytes $payloadBytes) -ne ([string]$payload.sha256).ToUpperInvariant()) {
            throw "Generated ASAR failed payload verification: $($payload.archivePath)"
        }
    }
    $indexBytes = Read-AsarFileBytes -ArchivePath $Path -Header $header -InternalPath "AppFiles/index.html"
    $indexText = (New-Object Text.UTF8Encoding($false)).GetString($indexBytes)
    if (-not $indexText.Contains([string]$Script:Manifest.indexMarker)) {
        throw "Generated ASAR does not contain the patch marker."
    }
}

function Test-DirectoryWritable {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $probe = Join-Path $Directory (".ad-zh-write-test-{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        $stream = [IO.File]::Open($probe, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
        Remove-Item -LiteralPath $probe -Force
        return $true
    }
    catch {
        if (Test-Path -LiteralPath $probe -PathType Leaf) {
            try { Remove-Item -LiteralPath $probe -Force } catch { }
        }
        return $false
    }
}

function Quote-ProcessArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '[\s"]') { return $Value }
    return '"' + ($Value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

function Restart-Elevated {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameRoot,
        [Parameter(Mandatory = $true)][string]$RequestedAction
    )
    $hostExecutable = (Get-Process -Id $PID).Path
    $arguments = @(
        "-NoLogo",
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", (Quote-ProcessArgument -Value $Script:ScriptPath),
        "-Action", $RequestedAction,
        "-GameRoot", (Quote-ProcessArgument -Value $ResolvedGameRoot),
        "-Elevated"
    ) -join " "
    Write-Step "Write access is unavailable. Requesting administrator permission for the game directory only."
    $process = Start-Process -FilePath $hostExecutable -ArgumentList $arguments -Verb RunAs -Wait -PassThru
    exit $process.ExitCode
}

function Assert-GameNotRunning {
    param([Parameter(Mandatory = $true)][string]$ResolvedGameRoot)
    $rootPrefix = $ResolvedGameRoot.TrimEnd('\') + '\'
    $running = @(Get-Process -Name "Antimatter Dimensions" -ErrorAction SilentlyContinue | Where-Object {
        try {
            $_.Path -and $_.Path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            # If Windows denies access to the process path, treat it as the
            # target game rather than risking an in-use archive replacement.
            $true
        }
    })
    if ($running) { throw "Close Antimatter Dimensions before installing or removing the patch." }
}

function Assert-CompatibleOriginal {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameRoot,
        [Parameter(Mandatory = $true)][string]$AsarPath,
        [Parameter(Mandatory = $true)][string]$CurrentHash
    )
    if ($CurrentHash -ne ([string]$Script:Manifest.game.originalAsarSha256).ToUpperInvariant()) {
        throw "Unsupported app.asar SHA-256: $CurrentHash. Steam may have updated the game; no files were changed."
    }
    if ((Get-Item -LiteralPath $AsarPath).Length -ne [int64]$Script:Manifest.game.originalAsarSize) {
        throw "The app.asar size does not match the supported build."
    }
    $gameVersion = Get-GameVersionFromAsar -AsarPath $AsarPath
    if ($gameVersion -ne [string]$Script:Manifest.game.version) {
        throw "Unsupported in-game version: $gameVersion"
    }
    $appManifest = Get-AppManifestForGameRoot -ResolvedGameRoot $ResolvedGameRoot
    if (-not $appManifest) { throw "Steam appmanifest_1399720.acf was not found for this installation." }
    if ($appManifest.AppId -ne [string]$Script:Manifest.game.appId -or
        $appManifest.BuildId -ne [string]$Script:Manifest.game.buildId) {
        throw "Unsupported Steam build. Expected $($Script:Manifest.game.buildId), found $($appManifest.BuildId)."
    }
}

function Ensure-OriginalBackup {
    param([Parameter(Mandatory = $true)][string]$AsarPath)
    $originalHash = ([string]$Script:Manifest.game.originalAsarSha256).ToUpperInvariant()
    $backupDirectory = Join-Path $Script:StateDirectory ("backups\{0}" -f $originalHash)
    $backupPath = Join-Path $backupDirectory "app.asar"
    if (-not (Test-Path -LiteralPath $backupDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $backupDirectory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
        if ((Get-Sha256 -Path $backupPath) -ne $originalHash) {
            throw "Existing backup failed SHA-256 verification: $backupPath"
        }
        return $backupPath
    }
    $temporary = Join-Path $backupDirectory ("app.{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        [IO.File]::Copy($AsarPath, $temporary, $false)
        if ((Get-Sha256 -Path $temporary) -ne $originalHash) { throw "New backup failed SHA-256 verification." }
        [IO.File]::Move($temporary, $backupPath)
        return $backupPath
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Resolve-InstallSource {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameRoot,
        [Parameter(Mandatory = $true)][string]$AsarPath,
        [Parameter(Mandatory = $true)][string]$CurrentHash,
        [object]$State
    )
    $originalHash = ([string]$Script:Manifest.game.originalAsarSha256).ToUpperInvariant()
    if ($CurrentHash -eq $originalHash) {
        Assert-CompatibleOriginal -ResolvedGameRoot $ResolvedGameRoot -AsarPath $AsarPath -CurrentHash $CurrentHash
        return [pscustomobject]@{
            OriginalPath = $AsarPath
            BackupPath = $null
            IsUpgrade = $false
        }
    }

    # Never stack a new patch on top of modified ASAR bytes. A direct upgrade
    # is allowed only when the active archive, state file, old marker, original
    # hash, and external backup all prove that this installer owns the current
    # patch. The new archive is then rebuilt from the pristine backup.
    if (-not $State -or [string]$State.status -ne "installed" -or
        -not $State.patchedSha256 -or $CurrentHash -ne ([string]$State.patchedSha256).ToUpperInvariant()) {
        throw "Unsupported app.asar SHA-256: $CurrentHash. Steam may have updated the game; no files were changed."
    }
    if (-not $State.patchVersion -or [string]$State.patchVersion -eq [string]$Script:Manifest.patchVersion) {
        throw "Patch state matches the current version but not its expected installation state. Refusing to overwrite."
    }
    if ($Script:CompatibleUpgradeVersions -notcontains [string]$State.patchVersion) {
        throw "Installed patch version $($State.patchVersion) is not a supported upgrade source. Refusing to downgrade or overwrite it."
    }
    if (-not $State.originalSha256 -or ([string]$State.originalSha256).ToUpperInvariant() -ne $originalHash) {
        throw "The installed patch was created from a different original game archive. Refusing to upgrade."
    }
    if (-not $State.steamBuildId -or [string]$State.steamBuildId -ne [string]$Script:Manifest.game.buildId) {
        throw "The installed patch belongs to a different Steam build. Refusing to upgrade."
    }

    $sameGameRoot = Test-SamePath -Left ([string]$State.gameRoot) -Right $ResolvedGameRoot
    if (-not $sameGameRoot -and (Test-Path -LiteralPath ([string]$State.gameRoot) -PathType Container)) {
        throw "Patch state belongs to another existing game directory: $($State.gameRoot)"
    }

    $header = Read-AsarHeader -Path $AsarPath
    $indexBytes = Read-AsarFileBytes -ArchivePath $AsarPath -Header $header -InternalPath "AppFiles/index.html"
    $indexText = (New-Object Text.UTF8Encoding($false)).GetString($indexBytes)
    $oldMarker = "AD-ZH-CN-PATCH:$([string]$State.patchVersion)"
    if (-not $indexText.Contains($oldMarker)) {
        throw "The active archive does not contain the marker recorded by the installed patch. Refusing to upgrade."
    }

    $backupPath = [string]$State.backupPath
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or (Get-Sha256 -Path $backupPath) -ne $originalHash) {
        throw "Verified original backup is unavailable: $backupPath"
    }
    Assert-CompatibleOriginal -ResolvedGameRoot $ResolvedGameRoot -AsarPath $backupPath -CurrentHash $originalHash
    return [pscustomobject]@{
        OriginalPath = $backupPath
        BackupPath = $backupPath
        IsUpgrade = $true
    }
}

function Replace-FileAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Replacement,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $directory = Split-Path -Parent $Destination
    $rollback = Join-Path $directory (".ad-zh-rollback-{0}.asar" -f [Guid]::NewGuid().ToString("N"))
    [IO.File]::Replace($Replacement, $Destination, $rollback, $true)
    if (Test-Path -LiteralPath $rollback -PathType Leaf) {
        Remove-Item -LiteralPath $rollback -Force
    }
}

function Show-Status {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameRoot,
        [object]$State
    )
    $asarPath = Join-Path $ResolvedGameRoot "resources\app.asar"
    $currentHash = Get-Sha256 -Path $asarPath
    $originalHash = ([string]$Script:Manifest.game.originalAsarSha256).ToUpperInvariant()
    Write-Step "Game directory: $ResolvedGameRoot"
    Write-Step "Current app.asar SHA-256: $currentHash"
    if ($currentHash -eq $originalHash) {
        Write-Step "Status: supported original build (patch is not installed)."
        return
    }
    if ($State -and $State.patchedSha256 -and
        $currentHash -eq ([string]$State.patchedSha256).ToUpperInvariant() -and
        [string]$State.patchVersion -eq [string]$Script:Manifest.patchVersion) {
        Write-Step "Status: Simplified Chinese patch $($State.patchVersion) is installed."
        return
    }
    if ($State -and $State.patchedSha256 -and $State.patchVersion -and $State.originalSha256 -and
        $currentHash -eq ([string]$State.patchedSha256).ToUpperInvariant() -and
        ([string]$State.originalSha256).ToUpperInvariant() -eq $originalHash -and
        $Script:CompatibleUpgradeVersions -contains [string]$State.patchVersion) {
        Write-Step "Status: older Simplified Chinese patch $($State.patchVersion) is installed; run Install to upgrade safely."
        return
    }
    try {
        $header = Read-AsarHeader -Path $asarPath
        $indexBytes = Read-AsarFileBytes -ArchivePath $asarPath -Header $header -InternalPath "AppFiles/index.html"
        $indexText = (New-Object Text.UTF8Encoding($false)).GetString($indexBytes)
        if ($indexText.Contains([string]$Script:Manifest.indexMarker)) {
            Write-Step "Status: patch marker exists, but local state does not match. Automatic overwrite is disabled."
            return
        }
    }
    catch { }
    Write-Step "Status: unknown or updated game archive. The patch will refuse to overwrite it."
}

function Install-Patch {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameRoot,
        [object]$State
    )
    Assert-GameNotRunning -ResolvedGameRoot $ResolvedGameRoot
    if ($State -and [string]$State.status -in @("installed", "installing") -and $State.gameRoot -and
        -not (Test-SamePath -Left ([string]$State.gameRoot) -Right $ResolvedGameRoot) -and
        (Test-Path -LiteralPath ([string]$State.gameRoot) -PathType Container)) {
        # The state format intentionally owns one installation. Refuse to
        # overwrite that ownership record while its original target still
        # exists; otherwise the first copy could no longer be uninstalled.
        throw "This Windows account already manages a patch in another game directory: $($State.gameRoot). Uninstall that copy before patching a second installation."
    }
    $resources = Join-Path $ResolvedGameRoot "resources"
    $asarPath = Join-Path $resources "app.asar"
    $currentHash = Get-Sha256 -Path $asarPath
    if ($State -and $State.patchedSha256 -and
        $currentHash -eq ([string]$State.patchedSha256).ToUpperInvariant() -and
        [string]$State.patchVersion -eq [string]$Script:Manifest.patchVersion) {
        Assert-PayloadIntegrity
        Assert-PatchedAsar -Path $asarPath
        if ([string]$State.status -eq "installing") {
            $State.status = "installed"
            Write-JsonFileAtomic -Value $State -Path $Script:StatePath
            Write-Step "Recovered an interrupted installation state after verifying the installed archive."
        }
        elseif ([string]$State.status -ne "installed") {
            throw "The installed archive matches this patch, but its state is '$($State.status)'. Refusing to guess ownership."
        }
        Write-Step "Patch $($Script:Manifest.patchVersion) is already installed."
        return
    }
    $installSource = Resolve-InstallSource -ResolvedGameRoot $ResolvedGameRoot -AsarPath $asarPath `
        -CurrentHash $currentHash -State $State
    Assert-PayloadIntegrity
    if (-not (Test-DirectoryWritable -Directory $resources)) {
        if (-not $Elevated) { Restart-Elevated -ResolvedGameRoot $ResolvedGameRoot -RequestedAction "Install" }
        throw "Administrator mode still cannot write to the resources directory."
    }

    $backupPath = if ($installSource.BackupPath) {
        [string]$installSource.BackupPath
    }
    else {
        Ensure-OriginalBackup -AsarPath ([string]$installSource.OriginalPath)
    }
    $temporary = Join-Path $resources (".app.asar.zh-cn.{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        if ([bool]$installSource.IsUpgrade) {
            Write-Step "Upgrading patch $($State.patchVersion) to $($Script:Manifest.patchVersion) from the verified original backup..."
        }
        else {
            Write-Step "Building a patched ASAR from the verified local game archive..."
        }
        Build-PatchedAsar -OriginalPath ([string]$installSource.OriginalPath) -OutputPath $temporary
        Assert-PatchedAsar -Path $temporary
        $patchedHash = Get-Sha256 -Path $temporary

        $stateValue = [ordered]@{
            schemaVersion = 1
            status = "installing"
            patchVersion = [string]$Script:Manifest.patchVersion
            gameRoot = $ResolvedGameRoot
            originalSha256 = ([string]$Script:Manifest.game.originalAsarSha256).ToUpperInvariant()
            patchedSha256 = $patchedHash
            backupPath = $backupPath
            steamBuildId = [string]$Script:Manifest.game.buildId
            installedAt = [DateTime]::UtcNow.ToString("o")
        }
        Write-JsonFileAtomic -Value $stateValue -Path $Script:StatePath
        Replace-FileAtomically -Replacement $temporary -Destination $asarPath
        if ((Get-Sha256 -Path $asarPath) -ne $patchedHash) { throw "Installed archive failed final SHA-256 verification." }
        $stateValue.status = "installed"
        Write-JsonFileAtomic -Value $stateValue -Path $Script:StatePath
        Write-Step "Patch installed successfully. Original backup: $backupPath"
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}

function Uninstall-Patch {
    param(
        [Parameter(Mandatory = $true)][string]$ResolvedGameRoot,
        [object]$State
    )
    Assert-GameNotRunning -ResolvedGameRoot $ResolvedGameRoot
    if (-not $State) { throw "No patch state exists. Refusing to guess which archive should be restored." }

    $resources = Join-Path $ResolvedGameRoot "resources"
    $asarPath = Join-Path $resources "app.asar"
    $currentHash = Get-Sha256 -Path $asarPath
    $originalHash = ([string]$Script:Manifest.game.originalAsarSha256).ToUpperInvariant()
    $sameGameRoot = Test-SamePath -Left ([string]$State.gameRoot) -Right $ResolvedGameRoot
    if (-not $sameGameRoot) {
        # Steam can move an installed game to another library. Accept that
        # narrow case only when the old installation no longer exists, the
        # current archive is exactly the one recorded by this patch, and the
        # new Steam manifest still identifies the supported build. If both
        # paths exist, this may be a second copy and the global state is not
        # sufficient to decide which installation owns the backup.
        if (Test-Path -LiteralPath ([string]$State.gameRoot) -PathType Container) {
            throw "Patch state belongs to another existing game directory: $($State.gameRoot)"
        }
        if (-not $State.patchedSha256 -or $currentHash -ne ([string]$State.patchedSha256).ToUpperInvariant()) {
            throw "The game directory changed and its app.asar does not match the archive installed by this patch."
        }
        $movedManifest = Get-AppManifestForGameRoot -ResolvedGameRoot $ResolvedGameRoot
        if (-not $movedManifest -or
            $movedManifest.AppId -ne [string]$Script:Manifest.game.appId -or
            $movedManifest.BuildId -ne [string]$Script:Manifest.game.buildId) {
            throw "The game directory changed and the new Steam manifest does not match the supported build."
        }
        Write-Step "Detected a Steam library move. The verified installation will be restored at its new location."
    }
    if ($currentHash -eq $originalHash) {
        if ([string]$State.status -ne "uninstalled") {
            $State.status = "uninstalled"
            $uninstalledAt = [DateTime]::UtcNow.ToString("o")
            if ($State.PSObject.Properties["uninstalledAt"]) {
                $State.uninstalledAt = $uninstalledAt
            }
            else {
                $State | Add-Member -MemberType NoteProperty -Name "uninstalledAt" -Value $uninstalledAt
            }
            Write-JsonFileAtomic -Value $State -Path $Script:StatePath
        }
        Write-Step "The original archive is already active. Nothing to remove."
        return
    }
    if (-not $State.patchedSha256 -or $currentHash -ne ([string]$State.patchedSha256).ToUpperInvariant()) {
        throw "Current app.asar is not the archive installed by this patch. Steam may have updated it; refusing to overwrite."
    }
    $backupPath = [string]$State.backupPath
    if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf) -or (Get-Sha256 -Path $backupPath) -ne $originalHash) {
        throw "Verified original backup is unavailable: $backupPath"
    }
    if (-not (Test-DirectoryWritable -Directory $resources)) {
        if (-not $Elevated) { Restart-Elevated -ResolvedGameRoot $ResolvedGameRoot -RequestedAction "Uninstall" }
        throw "Administrator mode still cannot write to the resources directory."
    }

    $temporary = Join-Path $resources (".app.asar.restore.{0}.tmp" -f [Guid]::NewGuid().ToString("N"))
    try {
        [IO.File]::Copy($backupPath, $temporary, $false)
        if ((Get-Sha256 -Path $temporary) -ne $originalHash) { throw "Restore copy failed SHA-256 verification." }
        Read-AsarHeader -Path $temporary | Out-Null
        Replace-FileAtomically -Replacement $temporary -Destination $asarPath
        if ((Get-Sha256 -Path $asarPath) -ne $originalHash) { throw "Restored archive failed final SHA-256 verification." }
        $State.status = "uninstalled"
        $State.gameRoot = $ResolvedGameRoot
        $uninstalledAt = [DateTime]::UtcNow.ToString("o")
        if ($State.PSObject.Properties["uninstalledAt"]) {
            $State.uninstalledAt = $uninstalledAt
        }
        else {
            $State | Add-Member -MemberType NoteProperty -Name "uninstalledAt" -Value $uninstalledAt
        }
        Write-JsonFileAtomic -Value $State -Path $Script:StatePath
        Write-Step "Patch removed successfully. The original archive was restored byte-for-byte."
    }
    finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force }
    }
}

try {
    $Script:Manifest = Read-JsonFile -Path $Script:ManifestPath
    if ([string]$Script:Manifest.patchVersion -ne $Script:SupportedManifestVersion) {
        throw "Unsupported patch manifest version."
    }
    $state = Get-ExistingState
    $resolvedRoot = Resolve-GameInstallation -RequestedRoot $GameRoot -State $state `
        -AllowInteractiveSelection:$Interactive
    if ($Interactive) {
        Write-Step "Selected game directory: $resolvedRoot"
        if ($Action -eq "Install") {
            $confirmation = Read-Host "Install the Simplified Chinese patch to this directory? [Y/N]"
            if ($confirmation -notmatch '^(?i:y|yes)$') {
                throw "Installation was cancelled; no files were changed."
            }
        }
    }
    switch ($Action) {
        "Check" { Show-Status -ResolvedGameRoot $resolvedRoot -State $state }
        "Install" { Install-Patch -ResolvedGameRoot $resolvedRoot -State $state }
        "Uninstall" { Uninstall-Patch -ResolvedGameRoot $resolvedRoot -State $state }
    }
    exit 0
}
catch {
    Write-Failure -Message $_.Exception.Message
    if ($env:AD_ZH_DEBUG -eq "1") {
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
    }
    exit 1
}
