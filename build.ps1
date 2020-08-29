<#
    .SYNOPSIS
        Really long comment blocks are tedious to keep commented in single-line mode.
    .DESCRIPTION
        Particularly when the comment must be frequently edited,
        as with the help and documentation for a function or script.
#>
param(
    [string]$SolutionPath = "",
    [string[]]$PropsPath,
    [string]$AssemblyOriginatorKeyFile = "",
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
        return $True
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
        return $False
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
        if ($Force -eq $False) {
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
        [string]$KeyPath

    )
    [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
    $propertyGroupNode = $doc.CreateElement("PropertyGroup", $doc.DocumentElement.NamespaceURI)

    $node = $doc.CreateElement("DelaySign", $doc.DocumentElement.NamespaceURI)
    $text = $doc.CreateTextNode("false")
    $node.AppendChild($text) | Out-Null
        
    $propertyGroupNode.AppendChild($node) | Out-Null
    $node = $doc.CreateElement("SignAssembly", $doc.DocumentElement.NamespaceURI)
    $text = $doc.CreateTextNode("true")
    $node.AppendChild($text) | Out-Null
    $propertyGroupNode.AppendChild($node) | Out-Null

    $node = $doc.CreateElement("AssemblyOriginatorKeyFile", $doc.DocumentElement.NamespaceURI)
    $text = $doc.CreateTextNode($KeyPath)
    $node.AppendChild($text) | Out-Null
    $propertyGroupNode.AppendChild($node) | Out-Null

    $doc.Project.AppendChild($propertyGroupNode) | Out-Null
    $doc.Save($ProjectPath)
}

function Build-Solution {
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

$revision = "unversioned"
$frameworkOption = ""
$location = Get-Location

try {
    # Set-Location $WorkingPath

    $SolutionPath = Resolve-Path $SolutionPath
    $WorkingPath = Split-Path $SolutionPath
    $PropsPath = Resolve-Path $PropsPath
    $AssemblyOriginatorKeyFile = Resolve-Path $AssemblyOriginatorKeyFile

    Write-Host "SolutionPath: $SolutionPath"
    Write-Host "WorkingPath: $WorkingPath"
    Write-Host "PropsPath: $PropsPath"
    Write-Host "KeyPath: $AssemblyOriginatorKeyFile"
    Write-Host ""
    
    Assert-NETCore -Version "3.1"
    if (!(Test-NET45 -SolutionPath $SolutionPath)) {
        $frameworkOption = "--framework netcoreapp3.1"
    }

    # check if there are any changes in the repository.
    Assert-Changes -WorkingPath $WorkingPath -Force:$Force

    $revision = Get-Revision -Path $WorkingPath


    # recored version to props file
    # $PropsPath | ForEach-Object {
    #     Initialize-Version $_
    #     Initialize-Sign -ProjectPath $_ -KeyPath $AssemblyOriginatorKeyFile
    # }
    # try {
    #     [xml]$doc = Get-Content $PropsPath -Encoding UTF8
    #     $doc.Project.PropertyGroup.Version = "$($doc.Project.PropertyGroup.FileVersion)-`$(TargetFramework)-$revision"
    #     if ("" -eq $AssemblyOriginatorKeyFile) {
    #         $doc.Project.PropertyGroup.AssemblyOriginatorKeyFile = $AssemblyOriginatorKeyFile
    #         $doc.Project.PropertyGroup.DelaySign = $FALSE
    #     }
    #     $doc.Save($PropsPath)

    #     $assemblyVersion = $doc.Project.PropertyGroup.AssemblyVersion
    #     $fileVersion = $doc.Project.PropertyGroup.FileVersion
    #     $version = $doc.Project.PropertyGroup.Version
    # }
    # catch {
    #     Write-Error $_.Exception.Message
    #     exit 1
    # }

    # build project
    Build-Solution -SolutionPath $SolutionPath -Framework $frameworkOption
    if ($LastExitCode -eq 0) {
        Write-Host ""
        Write-Host "AssemblyVersion: $assemblyVersion"
        Write-Host "FileVersion: $fileVersion"
        Write-Host "Version: $version"
        Write-Host "revision: $revision"
        Write-Host ""
    }
    else {
        Write-Error "build failed"
    }
}
finally {
    # revert props file
    if ($Force -eq $False) {
        $PropsPath | ForEach-Object {
            Restore-ProjectPath $_
        }
        # Invoke-Expression "git checkout `"$PropsPath`"" 2>&1
    }
    Set-Location $location
}
