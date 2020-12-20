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
    [ValidateSet('build', 'publish', 'pack')]
    [string]$Task = "build",
    [string]$KeyPath = "",
    [string]$LogPath = "",
    [switch]$Sign,
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
            throw $changes
        }
    }
    catch {
        if ($Force -eq $false) {
            Write-Log "WorkingPath: $WorkingPath" -LogType "Error"
            Write-Log
            Write-Log $_.Exception.Message -LogType "Error"
            Write-Log
            Write-Log "git repository has changes. build aborted." -LogType "Error"
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

function Get-ProjectPaths {
    param(
        [string]$SolutionPath
    )
    $items = Invoke-Expression "dotnet sln `"$SolutionPath`" list"
    $directory = Split-Path $SolutionPath
    $items | ForEach-Object {
        if ($null -ne $_) {
            $path = Join-Path $directory $_
            if (Test-Path $path) {
                $path
            }
        }
    }
}

function Get-RepositoryPaths {
    param(
        [string]$SolutionPath
    )
    $location = Get-Location
    try {
        $repositoryPath = Split-Path $SolutionPath
        $items = @( $repositoryPath )
        Set-Location $repositoryPath
        Invoke-Expression "git submodule foreach --recursive -q pwd" | ForEach-Object {
            $items = $items + $_
        }
        return $items
    }
    finally {
        Set-Location $location        
    }
}

function Save-Repositories {
    param (
        [string]$SolutionPath
    )
    $items = Get-RepositoryPaths $SolutionPath

    $items | Sort-Object -Descending
    
}

function Get-ProjectType {
    param(
        [string]$ProjectPath
    )
    [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
    $doc.Project.Sdk
}

function Initialize-Version {
    param (
        [string]$ProjectPath,
        [string[]]$Frameworks
    )
    try {
        $revision = Get-Revision $ProjectPath
        [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
        if ($null -eq $doc.Project.PropertyGroup.FileVersion) {
            throw "there is no version"
        }
        $version = "$($doc.Project.PropertyGroup.FileVersion)-`$(TargetFramework)-$revision"
        $versions = $Frameworks | ForEach-Object { "$($doc.Project.PropertyGroup.FileVersion)-$_-$revision" }
        $doc.Project.PropertyGroup.Version = $version
        $doc.Save($ProjectPath)
        
        Write-Property "Path" $ProjectPath
        Write-Property "Version" $versions
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
        [switch]$Sign
    )
    [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
    $propertyGroupNode = $doc.CreateElement("PropertyGroup", $doc.DocumentElement.NamespaceURI)
    $delaySign = ("" -ne $KeyPath) -and ($false -eq $Sign);
    $signAssembly = $Sign;

    $node = $doc.CreateElement("DelaySign", $doc.DocumentElement.NamespaceURI)
    $text = $doc.CreateTextNode($delaySign ? "true" : "false")
    $node.AppendChild($text) | Out-Null
        
    $propertyGroupNode.AppendChild($node) | Out-Null
    $node = $doc.CreateElement("SignAssembly", $doc.DocumentElement.NamespaceURI)
    $text = $doc.CreateTextNode($signAssembly ? "true" : "false")
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

    Write-Property "DelaySign" "$($delaySign)"
    Write-Property "SignAssembly" "$($signAssembly)"
    Write-Property "AssemblyOriginatorKeyFile" $KeyPath
}

function Invoke-Build {
    param(
        [string]$SolutionPath,
        [string]$FrameworkOption,
        [ValidateSet('build', 'publish', 'pack')]
        [string]$Task = "build"
    )
    $expression = "dotnet $Task `"$SolutionPath`" $FrameworkOption --verbosity quiet --nologo --configuration Release"
    Invoke-Expression $expression | Tee-Object -Variable items | ForEach-Object {
        if ($_ -match "(.+): (warning CS\d+): (.+)") {
            Write-Log "## $($Matches[2])`n`n$($Matches[1])`n`n    $($Matches[3])" -LogType "Warning"
            Write-Log
        }
        elseif ($_ -match "(.+): (error CS\d+): (.+)") {
            Write-Log "## $($Matches[2])`n`n$($Matches[1])`n`n    $($Matches[3])" -LogType "Error"
            Write-Log
        }
        else {
            Write-Log $_
        }
    }
}

function Resolve-Solution {
    param(
        [string]$SolutionPath
    )
    if ([environment]::OSVersion.Platform -eq "Win32NT") {
        Write-Log "there is no problems to resolve."
    }
    else {
        $projectPaths = Get-ProjectPaths $SolutionPath
        $projectPaths | ForEach-Object {
            $projectType = Get-ProjectType $_
            if ($projectType -eq "Microsoft.NET.Sdk.WindowsDesktop") {
                Invoke-Expression "dotnet sln `"$SolutionPath`" remove `"$_`""
                Write-Log "The project cannot be built on the current platform.`n`n    $_" -LogType "Warning"
                Write-Log
            }
        }
    }
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

function Restore-SolutionPath {
    param(
        [string]$SolutionPath
    )
    $location = Get-Location
    try {
        Set-Location (Split-Path $SolutionPath)
        Invoke-Expression "git checkout `"$SolutionPath`"" 2>&1
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
    Add-Content -Path $LogPath -Value "$levelText $Header", ""
}

function Write-Log {
    param(
        [string]$Text = "",
        [ValidateSet('Output', 'Error', 'Warning')]
        [string]$LogType = "Output"
    )
    switch ($LogType) {
        "Output" { Write-Host $Text }
        "Error" { Write-Error $Text }
        "Warning" { Write-Warning $Text }
    }
    Add-Content -Path $LogPath -Value $Text
}

function Start-Log {
    Add-Content -Path $LogPath -Value "``````plain"
}

function Stop-Log {
    Add-Content -Path $LogPath -Value "``````"
}

function Write-Column {
    param(
        [string[]]$Columns
    )
    $items = ($Columns | ForEach-Object { "".PadRight($_.Length, '-') }) -join " | "
    $title = " | $($Columns -join " | ") | "
    $separator = " | $($items) | "
    Add-Content -Path $LogPath -Value $title, $separator
}

function Write-Property {
    param(
        [string]$Name,
        [string[]]$Values
    )
    if ($Values.Length -eq 1) {
        Write-Host "$($Name): $($Values[0])"
        Add-Content -Path $LogPath -Value " | $Name | $($Values[0]) | "
    }
    else {
        Write-Host "$($Name):"
        $Values | ForEach-Object { Write-Host "    $_" }
        Add-Content -Path $LogPath -Value " | $Name | $($Values -join "<br>") | "
    }
}

Save-Repositories $SolutionPath

return;
$dateTime = Get-Date
if ($LogPath -eq "") {
    $dateTimeText = $dateTime.ToString("yyyy-MM-dd_hh-mm-ss")
    $logDirectory = Join-Path (Get-Location) "logs"
    if (!(Test-Path $logDirectory)) {
        New-Item $logDirectory -ItemType Directory
    }
    $LogPath = Join-Path $logDirectory "$($dateTimeText).md"
}
Set-Content $LogPath "" -Encoding UTF8

$location = Get-Location
try {
    Write-Header "Initialize"
    
    $frameworkOption = ""
    $frameworks = "netcoreapp3.1", "net45"
    $SolutionPath = Resolve-Path $SolutionPath
    $WorkingPath = Split-Path $SolutionPath
    $PropsPath = Resolve-Path $PropsPath
    if ("" -eq $KeyPath) {
        if ($Sign -eq $true) {
            throw "Unable to sign because the key path does not exist.";
        }
    }
    else {
        $KeyPath = Resolve-Path $KeyPath
    }

    Write-Column "Name", "Value"
    Write-Property "DateTime" $dateTime.ToString()
    Write-Property "SolutionPath" $SolutionPath
    Write-Property "WorkingPath" $WorkingPath
    Write-Property "PropsPath" $PropsPath
    Write-Property "KeyPath" $KeyPath
    Write-Property "OmitSign" $OmitSign
    Write-Property "Force" $Force
    Write-Log ""

    Write-Header "TargetFrameworks"
    Start-Log
    Assert-NETCore -Version "3.1"
    if (!(Test-NET45 -SolutionPath $SolutionPath)) {
        $frameworkOption = "--framework netcoreapp3.1"
        $frameworks = , "netcoreapp3.1"
        Write-Log "netcoreapp3.1"
    }
    else {
        Write-Log "netcoreapp3.1"
        Write-Log "net45"
    }
    Stop-Log
    Write-Log

    # check if there are any changes in the repository.
    Write-Header "Repository changes"
    Start-Log
    Assert-Changes -WorkingPath $WorkingPath -Force:$Force
    $PropsPath | ForEach-Object {
        $directory = Split-Path $_
        Assert-Changes -WorkingPath $directory -Force:$Force
    }
    Write-Log "no changes."
    Stop-Log
    Write-Log

    # recored version and keypath to props file
    Write-Header "Set Information to props files"
    $PropsPath | ForEach-Object {
        Write-Column "Name", "Value"
        Initialize-Version $_ $frameworks
        Initialize-Sign -ProjectPath $_ -KeyPath $KeyPath -Sign:$Sign
        Write-Log
    }

    # resolve solution
    Write-Header "Resolve Solution"
    Resolve-Solution $SolutionPath
    Write-Log
 
    # build project
    Write-Header "Build"
    Invoke-Build -SolutionPath $SolutionPath -Framework $frameworkOption -Task $Task
    Write-Log

    # record build result
    Write-Header "Result"
    Start-Log
    if ($LastExitCode -eq 0) {
        $lastTime = Get-Date
        $timeSpan = $lastTime - $dateTime
        Write-Log "Start Time  : $($dateTime.ToString())"
        Write-Log "End Time    : $($lastTime.ToString())"
        Write-Log "Elapsed time: $timeSpan"
        Write-Log "build completed."
    }
    else {
        Write-Log "build failed" -LogType "Error"
    }
    Write-Host
    Write-Host "LogPath: $LogPath"
    Write-Host
    Stop-Log
}
finally {
    # revert props file
    if ($Force -eq $false) {
        $PropsPath | ForEach-Object {
            Restore-ProjectPath $_
        }
        Restore-SolutionPath $SolutionPath
    }
    Set-Location $location
}
