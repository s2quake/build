<#
    .SYNOPSIS
        Really long comment blocks are tedious to keep commented in single-line mode.
    .DESCRIPTION
        Particularly when the comment must be frequently edited,
        as with the help and documentation for a function or script.
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
        Write-Error $_.Exception.Message
        Write-Warning "Please visit the site below and install it."
        Write-Warning "https://dotnet.microsoft.com/download/dotnet-core/$Version"
        Write-Host ""
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
            Write-Error $WorkingPath
            Write-Error $_.Exception.Message
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
        Write-Error $_.Exception.Message
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
        Write-Error $_.Exception.Message
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
    Invoke-Expression "dotnet build `"$SolutionPath`" $FrameworkOption --verbosity minimal --nologo --configuration Release"
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

$location = Get-Location
try {
    $frameworkOption = ""
    $SolutionPath = Resolve-Path $SolutionPath
    $WorkingPath = Split-Path $SolutionPath
    $PropsPath = Resolve-Path $PropsPath
    if ("" -ne $AssemblyOriginatorKeyFile) {
        $AssemblyOriginatorKeyFile = Resolve-Path $AssemblyOriginatorKeyFile
    }

    Write-Host "SolutionPath: $SolutionPath"
    Write-Host "WorkingPath: $WorkingPath"
    Write-Host "PropsPath:"
    $PropsPath | ForEach-Object {
        Write-Host "    $_"
    }
    Write-Host "KeyPath: $AssemblyOriginatorKeyFile"
    Write-Host ""
    
    # validate to build with netcoreapp3.1 or net45
    Assert-NETCore -Version "3.1"
    if (!(Test-NET45 -SolutionPath $SolutionPath)) {
        $frameworkOption = "--framework netcoreapp3.1"
    }

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
    Invoke-Build -SolutionPath $SolutionPath -Framework $frameworkOption
    if ($LastExitCode -eq 0) {
        Write-Host ""
        Write-Host "build completed."
        Write-Host ""
    }
    else {
        Write-Error "build failed"
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
