<#
    .SYNOPSIS
        빌드
    .DESCRIPTION
        
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SolutionPath,
    [Parameter(Mandatory = $true)]
    [string[]]$PropsPath,
    [string]$AssemblyOriginatorKeyFile = "",
    [switch]$OmitSign,
    [switch]$Force
)

$dateTime = Get-Date
$dateTimeText = $dateTime.ToString("yyyy-MM-HH:mm:ss")
Write-Host $dateTimeText
$logPath = Join-Path $PSScriptRoot "$($dateTimeText).md"

function Assert-NETCore {
    param(
        [System.Version]$Version = "3.1"
    )
    try {
        [System.Version]$realVersion = dotnet --version
        if ($realVersion -lt $Version) {
            throw "NET Core $Version or higher version must be installed to build this project."
        }
    }
    catch {
        Write-Header "Error"
        Write-Log $_.Exception.Message -IsError
        Write-Log "Please visit the site below and install it." -IsWarning
        Write-Log "https://dotnet.microsoft.com/download/dotnet-core/$Version" -IsWarning
        Write-Log ""
        Write-Host 'Press any key to continue...';
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
        exit 1
    }
}

function Test-NET45 {
    param(
        [string]$SolutionPath
    )
    try {
        Invoke-Expression "dotnet msbuild `"$SolutionPath`" -t:GetReferenceAssemblyPaths -v:n -p:TargetFramework=net45" | Out-Null
        if ($LastExitCode -ne 0) {
            throw "Unable to build to .NET Framework 4.5."
        }
        return $true
    }
    catch {
        Write-Warning $_.Exception.Message
        if ([environment]::OSVersion.Platform -eq "Unix") {
            Write-Warning "To build this project with .NET Framework 4.5, visit site below and install the latest version of mono."
            Write-Warning "https://www.mono-project.com"
        }
        elseif ([environment]::OSVersion.Platform -eq "Win32NT") {
            Write-Warning "To build this project with .NET Framework 4.5, you must install tools and component below."
            Write-Warning "https://visualstudio.microsoft.com/downloads"
            Write-Warning "Install `"Visual Studio 2019 Community`" or `"Build Tools for Visual Studio 2019`""
            Write-Warning "In addition, install the following items on the `"Individual Components`" tab of the `"Visual Studio Installer`"."
            Write-Warning "    .NET Core 3.1 LTS Runtime"
            Write-Warning "    .NET Core SDK"
            Write-Warning "    .NET Framework 4.5 targeting pack"
        }
        Write-Host ""
        return $false
    }
}

function Assert-Changes {
    param (
        [string]$WorkingPath,
        [switch]$Force
    )
    $location = Get-Location
    try {
        Set-Location $WorkingPath
        $changes = Invoke-Expression "git status --porcelain"
        if ($changes) {
            throw "git repository has changes. build aborted."
        }
    }
    catch {
        if ($Force -eq $false) {
            Write-Header "Error"
            Write-Log "WorkingPath: $WorkingPath" -IsError
            Write-Log $_.Exception.Message -IsError
            exit 1
        }
    }
    finally {
        Set-Location $location
    }
}

function Get-Revision {
    param(
        [string]$Path
    )
    $location = Get-Location
    try {
        if (Test-Path -Path $Path) {
            if (Test-Path -Path $Path -PathType Container) {
                Set-Location -Path $Path
            }
            else {
                Set-Location -Path (Split-Path $Path)
            }
        }
        $revision = Invoke-Expression -Command "git rev-parse HEAD" 2>&1 -ErrorVariable errout
        if ($LastExitCode -ne 0) {
            throw $errout
        }
        return $revision
    }
    catch {
        Write-Log $_.Exception.Message -IsError
        return $null
    }
    finally {
        Set-Location $location
    }
}

function Initialize-Version {
    param (
        [string]$ProjectPath
    )
    try {
        $revision = Get-Revision $ProjectPath
        [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
        if ($null -eq $doc.Project.PropertyGroup.FileVersion) {
            throw "there is no version"
        }
        $doc.Project.PropertyGroup.Version = "$($doc.Project.PropertyGroup.FileVersion)-`$(TargetFramework)-$revision"
        $doc.Save($ProjectPath)
    }
    catch {
        Write-Header "Error"
        Write-Log $_.Exception.Message -IsError
        exit 1
    }
}

function Initialize-Sign {
    param (
        [string]$ProjectPath,
        [string]$KeyPath,
        [switch]$OmitSign
    )
    [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
    $propertyGroupNode = $doc.CreateElement("PropertyGroup", $doc.DocumentElement.NamespaceURI)

    $node = $doc.CreateElement("DelaySign", $doc.DocumentElement.NamespaceURI)
    $text = $doc.CreateTextNode("false")
    $node.AppendChild($text) | Out-Null
        
    $propertyGroupNode.AppendChild($node) | Out-Null
    $node = $doc.CreateElement("SignAssembly", $doc.DocumentElement.NamespaceURI)
    if ($OmitSign) {
        $text = $doc.CreateTextNode("false")
    }
    else {
        $text = $doc.CreateTextNode("true")
    }
    $node.AppendChild($text) | Out-Null
    $propertyGroupNode.AppendChild($node) | Out-Null

    $node = $doc.CreateElement("AssemblyOriginatorKeyFile", $doc.DocumentElement.NamespaceURI)
    $text = $doc.CreateTextNode($KeyPath)
    $node.AppendChild($text) | Out-Null
    $propertyGroupNode.AppendChild($node) | Out-Null

    $doc.Project.AppendChild($propertyGroupNode) | Out-Null
    $doc.Save($ProjectPath)
}

function Invoke-Build {
    param(
        [string]$SolutionPath,
        [string]$FrameworkOption
    )
    Invoke-Expression "dotnet build `"$SolutionPath`" $FrameworkOption --verbosity minimal --nologo --configuration Release" | Tee-Object -Append $logPath
}

function Restore-ProjectPath {
    param(
        [string]$ProjectPath
    )
    $location = Get-Location
    try {
        Set-Location (Split-Path $ProjectPath)
        Invoke-Expression "git checkout `"$ProjectPath`"" 2>&1
    }
    finally {
        Set-Location $location        
    }
}

function Write-Header {
    param(
        [string]$Header,
        [int]$Level = 0
    )
    $levelText = "".PadRight($Level + 1, '#')
    Write-Host "$levelText $Header"
    Add-Content -Path $logPath -Value "$levelText $Header", ""
}

function Write-Log {
    param(
        [string]$Text,
        [switch]$IsError,
        [switch]$IsWarning
    )
    if ($IsError) {
        Write-Error $Text
    }
    elseif ($IsWarning) {
        Write-Warning $Text
    }
    else {
        Write-Host $Text
    }
    Add-Content -Path $logPath -Value $Text, ""
}

function Write-Column {
    param(
        [string[]]$Columns
    )
    $items = ($Columns | ForEach-Object { "".PadRight($_.Length, '-') }) -join " | "
    $title = "| $($Columns -join " | ") |"
    $separator = "| $($items) |"
    Add-Content -Path $logPath -Value $title, $separator
}

function Write-Row {
    param(
        [string[]]$Fields
    )
    $text = "| $($Fields -join " | ") |"
    Add-Content -Path $logPath -Value $text
}

$location = Get-Location
try {
    Write-Header "Initialize"

    $frameworkOption = ""
    $SolutionPath = Resolve-Path $SolutionPath
    $WorkingPath = Split-Path $SolutionPath
    $PropsPath = Resolve-Path $PropsPath
    if ("" -ne $AssemblyOriginatorKeyFile) {
        $AssemblyOriginatorKeyFile = Resolve-Path $AssemblyOriginatorKeyFile
    }

    Write-Column "Name", "Value"
    Write-Row "DateTime", $dateTime
    Write-Row "SolutionPath", $SolutionPath
    Write-Row "WorkingPath", $WorkingPath
    $PropsPath | ForEach-Object {
        Write-Row "PropsPath", $_
    }
    Write-Row "KeyPath", $AssemblyOriginatorKeyFile
    Write-Row "OmitSign", $OmitSign
    Write-Row "Force", $Force
    Write-Log ""

    Write-Host "SolutionPath: $SolutionPath"
    Write-Host "WorkingPath: $WorkingPath"
    Write-Host "PropsPath:"
    $PropsPath | ForEach-Object {
        Write-Host "    $_"
    }
    Write-Host "KeyPath: $AssemblyOriginatorKeyFile"
    Write-Host ""
    
    # validate to build with netcoreapp3.1 or net45
    Write-Header "Framework Option"
    Assert-NETCore -Version "3.1"
    if (!(Test-NET45 -SolutionPath $SolutionPath)) {
        $frameworkOption = "--framework netcoreapp3.1"
        Write-Log $frameworkOption
    } else {
        Write-Log "all"
    }
    Write-Log ""

    # check if there are any changes in the repository.
    Assert-Changes -WorkingPath $WorkingPath -Force:$Force
    $PropsPath | ForEach-Object {
        $directory = Split-Path $_
        Assert-Changes -WorkingPath $directory -Force:$Force
    }

    # recored version and keypath to props file
    $PropsPath | ForEach-Object {
        Initialize-Version $_
        if ("" -ne $AssemblyOriginatorKeyFile) {
            Initialize-Sign -ProjectPath $_ -KeyPath $AssemblyOriginatorKeyFile -OmitSign:$OmitSign
        }
    }
 
    # build project
    Write-Header "Build"
    Invoke-Build -SolutionPath $SolutionPath -Framework $frameworkOption
    Write-Log ""

    # record build result
    Write-Header "Result"
    if ($LastExitCode -eq 0) {
        Write-Log "$(Get-Date)"
        Write-Log "build completed."
        Write-Log ""
    }
    else {
        Write-Log "build failed" -IsError
    }
}
finally {
    # revert props file
    if ($Force -eq $false) {
        $PropsPath | ForEach-Object {
            Restore-ProjectPath $_
        }
    }
    Set-Location $location
}
