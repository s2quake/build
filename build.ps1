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
    [string]$KeyPath = "",
    [switch]$OmitSign,
    [switch]$IsPrivate,
    [switch]$Force
)

$dateTime = Get-Date
$dateTimeText = $dateTime.ToString("yyyy-MM-HH:mm:ss")
Write-Host $dateTimeText
# $logPath = Join-Path $PSScriptRoot "$($dateTimeText).md"
$logPath = Join-Path $PSScriptRoot "build.md"
Set-Content $logPath ""

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
        Write-Log $_.Exception.Message -LogType "Error"
        Write-Log "Please visit the site below and install it." -LogType "Warning"
        Write-Log "https://dotnet.microsoft.com/download/dotnet-core/$Version" -LogType "Warning"
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
            Write-Log "WorkingPath: $WorkingPath" -LogType "Error"
            Write-Log $_.Exception.Message -LogType "Error"
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
        Write-Log $_.Exception.Message -LogType "Error"
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
        $version = "$($doc.Project.PropertyGroup.FileVersion)-`$(TargetFramework)-$revision"
        $doc.Project.PropertyGroup.Version = $version
        $doc.Save($ProjectPath)
        
        Write-Property "Path" $ProjectPath
        Write-Property "Version" $version
    }
    catch {
        Write-Log $_.Exception.Message -LogType "Error"
        exit 1
    }
}

function Initialize-Sign {
    param (
        [string]$ProjectPath,
        [string]$KeyPath,
        [switch]$OmitSign,
        [switch]$IsPrivate
    )
    [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
    $propertyGroupNode = $doc.CreateElement("PropertyGroup", $doc.DocumentElement.NamespaceURI)

    $node = $doc.CreateElement("DelaySign", $doc.DocumentElement.NamespaceURI)
    if ($IsPrivate) {
        $text = $doc.CreateTextNode("false")
    }
    else {
        $text = $doc.CreateTextNode("true")
    }
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

    if ($KeyPath) {
        $node = $doc.CreateElement("AssemblyOriginatorKeyFile", $doc.DocumentElement.NamespaceURI)
        $text = $doc.CreateTextNode($KeyPath)
        $node.AppendChild($text) | Out-Null
        $propertyGroupNode.AppendChild($node) | Out-Null
    }

    $doc.Project.AppendChild($propertyGroupNode) | Out-Null
    $doc.Save($ProjectPath)

    Write-Property "DelaySign" "$(!$IsPrivate)"
    Write-Property "SignAssembly" "$(!$OmitSign)"
    Write-Property "AssemblyOriginatorKeyFile" $KeyPath
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
        [string]$Text = "",
        [ValidateSet('Output', 'Error', 'Warning')]
        [string]$LogType = "Output",
        [ValidateSet('None', 'Code')]
        [string]$Style = "None",
        [switch]$NoNewLine
    )
    $New
    switch ($LogType) {
        "Output" { Write-Host $Text -NoNewline:$NoNewLine }
        "Error" { Write-Error $Text -NoNewline:$NoNewLine }
        "Warning" { Write-Warning $Text -NoNewline:$NoNewLine }
    }
    switch ($Style) {
        "None" { Add-Content -Path $logPath -Value $Text -NoNewline:$NoNewLine }
        "Code" { Add-Content -Path $logPath -Value "    $Text" -NoNewline:$NoNewLine }
    }
    
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

function Write-Property {
    param(
        [string]$Name,
        [string[]]$Values
    )
    if ($Values.Length -eq 1) {
        Write-Host "$($Name): $($Values[0])"
        Add-Content -Path $logPath -Value "| $Name | $($Values[0]) |"
    }
    else {
        Write-Host "$($Name):"
        $Values | ForEach-Object { Write-Host "    $_" }
        Add-Content -Path $logPath -Value "| $Name | $($Values -join "<br>") |"
    }
}

$location = Get-Location
try {
    Write-Header "Initialize"

    $frameworkOption = ""
    $SolutionPath = Resolve-Path $SolutionPath
    $WorkingPath = Split-Path $SolutionPath
    $PropsPath = Resolve-Path $PropsPath
    if ("" -ne $KeyPath) {
        $KeyPath = Resolve-Path $KeyPath
    }

    Write-Column "Name", "Value"
    Write-Property "DateTime" $dateTime
    Write-Property "SolutionPath" $SolutionPath
    Write-Property "WorkingPath" $WorkingPath
    Write-Property "PropsPath" $PropsPath
    Write-Property "KeyPath" $KeyPath
    Write-Property "OmitSign" $OmitSign
    Write-Property "Force" $Force
    Write-Log ""

    Write-Header "Framework Option"
    Assert-NETCore -Version "3.1"
    if (!(Test-NET45 -SolutionPath $SolutionPath)) {
        $frameworkOption = "--framework netcoreapp3.1"
        Write-Log $frameworkOption
    }
    else {
        Write-Log "all"
        Write-Log
    }

    # check if there are any changes in the repository.
    Write-Header "Repository changes"
    Assert-Changes -WorkingPath $WorkingPath -Force:$Force
    $PropsPath | ForEach-Object {
        $directory = Split-Path $_
        Assert-Changes -WorkingPath $directory -Force:$Force
    }
    Write-Log "no changes."
    Write-Log

    # recored version and keypath to props file
    Write-Header "Set Information to props files"
    $PropsPath | ForEach-Object {
        Write-Column "Name", "Value"
        Initialize-Version $_
        Initialize-Sign -ProjectPath $_ -KeyPath $KeyPath -OmitSign:$OmitSign -IsPrivate:$IsPrivate
        Write-Log
    }
 
    # build project
    Write-Header "Build"
    Invoke-Build -SolutionPath $SolutionPath -Framework $frameworkOption
    Write-Log

    # record build result
    Write-Header "Result"
    if ($LastExitCode -eq 0) {
        Write-Log "$(Get-Date)"
        Write-Log "build completed."
    }
    else {
        Write-Log "build failed" -LogType "Error"
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
