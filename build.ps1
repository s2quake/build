<#
    .SYNOPSIS
        빌드
    .DESCRIPTION
        
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$SolutionPath,
    [Parameter(Mandatory = $true)]
    [string[]]$PropPaths,
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

function Get-RepositoryChanges {
    [OutputType([string[]])]
    param (
        [string]$RepositoryPath
    )
    return Invoke-Expression "git -C `"$RepositoryPath`" status --porcelain"
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
    $platform = [environment]::OSVersion.Platform
    $repositoryPath = Split-Path $SolutionPath
    $items = @( $repositoryPath )
    Invoke-Expression "git -C `"$repositoryPath`" submodule foreach --recursive -q pwd" | ForEach-Object {
        $item = $_
        if ($platform -eq "Win32NT") {
            $item = $_ -replace "/(\w)(/.+)", "`$1:`$2"
            $item = $item -replace "/", "\"
        }
        $items = $items + $item
    }
    return $items
}

function Test-Stash {
    param (
        [string]$RepositoryPath,
        [guid]$Token
    )
    [array]$items = Invoke-Expression "git -C `"$RepositoryPath`" stash list"
    if (($items -is [array]) -and ($items.Length)) {
        if ($items[0] -match ".+$Token`$") {
            return $true
        }
    }
    return $false
}

function Restore-Repositories {
    param (
        [string]$SolutionPath,
        [guid]$Token,
        [switch]$Force
    )
    $items = Get-RepositoryPaths $SolutionPath
    $items | ForEach-Object {
        Invoke-Expression "git -C `"$_`" reset --hard -q"
        if ($Force -and (Test-Stash $_ $Token)) {
            Invoke-Expression "git -C `"$_`" stash pop -q"
        }
    }
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
    if ($tru -eq $delaySign) {
        $text = $doc.CreateTextNode("true")
    } 
    else {
        $text = $doc.CreateTextNode("false")
    }
    $node.AppendChild($text) | Out-Null
        
    $propertyGroupNode.AppendChild($node) | Out-Null
    $node = $doc.CreateElement("SignAssembly", $doc.DocumentElement.NamespaceURI)
    if ($true -eq $signAssembly) {
        $text = $doc.CreateTextNode("true")
    }
    else {
        $text = $doc.CreateTextNode("false")
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

    Write-Property "DelaySign" "$($delaySign)"
    Write-Property "SignAssembly" "$($signAssembly)"
    Write-Property "AssemblyOriginatorKeyFile" $KeyPath
}

function Step-RepositoryChanges {
    param(
        [string[]]$RepositoryPaths,
        [switch]$Force
    )
    try {
        $logType = "Error"
        if ($Force -eq $true) {
            $logType = "Warning"
        }
        $changes = @{}
        $RepositoryPaths | ForEach-Object {
            $itemChanges = Get-RepositoryChanges -RepositoryPath $_
            if ($itemChanges) {
                $changes[$_] = $itemChanges
            }
        }
        if ($changes.Count) {
            $changes.Keys | ForEach-Object {
                Write-Log $changes[$_] -Label $_ -LogType $logType
            }
            if ($Force -eq $false) {
                Write-Log "git repository has changes. build aborted." -LogType "Error"
                exit 1
            }
        }
        else {
            Start-Log
            Write-Log "no changes."
            Stop-Log
        }
    }
    finally {
    }
}

function Step-SaveRepositories {
    param (
        [string]$SolutionPath,
        [guid]$Token,
        [switch]$Force
    )
    $items = Get-RepositoryPaths $SolutionPath
    if ($Force) {
        $items | Sort-Object -Descending | ForEach-Object {
            Invoke-Expression "git -C `"$_`" stash save -q --message `"$Token`""
            if (Test-Stash $_ $Token) {
                Invoke-Expression "git -C `"$_`" stash apply -q"
            }
        }
    }
}

function Step-Build {
    param(
        [string]$SolutionPath,
        [string]$FrameworkOption,
        [ValidateSet('build', 'publish', 'pack')]
        [string]$Task = "build"
    )
    [string[]]$resultItems = $()
    $expression = "dotnet $Task `"$SolutionPath`" $FrameworkOption --verbosity quiet --nologo --configuration Release"
    Invoke-Expression $expression | Tee-Object -Variable items | ForEach-Object {
        $pattern = "^(?:\s+\d+\>)?([^\s].*)\((\d+|\d+,\d+|\d+,\d+,\d+,\d+)\)\s*:\s+(error|warning|info)\s+(\w{1,2}\d+)\s*:\s*(.*)$"
        if ($_ -match $pattern) {
            $path = $Matches[1]
            $location = $Matches[2]
            $type = $Matches[3]
            $typeValue = $Matches[4]
            $message = $Matches[5]
            switch ($type) {
                "error" {
                    Write-Error $_ 
                    Write-Column "Name", "Value"
                    Write-Property "Error" "<span style=`"color:red`">$typeValue</span>"
                    Write-Property "Path" $path
                    Write-Property "Location" $location
                    Write-Property "Message" $message
                    Write-Log "_________________"
                }
                "warning" {
                    Write-Warning $_ 
                    Write-Column "Name", "Value"
                    Write-Property "Warning" "<span style=`"color:yellow`">$typeValue</span>"
                    Write-Property "Path" $path
                    Write-Property "Location" $location
                    Write-Property "Message" $message
                    Write-Log "_________________"
                }
                "info" {
                    Write-Information $_ 
                    Write-Column "Name", "Value"
                    Write-Property "Information" $typeValue
                    Write-Property "Path" $path
                    Write-Property "Location" $location
                    Write-Property "Message" $message
                    Write-Log "_________________"
                }
            }
        }
        else {
            $resultItems += $_
        }
    }

    Start-Log
    Write-Log $resultItems
    Stop-Log
}

function Step-ResolveProp {
    param(
        [string[]]$PropPaths,
        [string[]]$Frameworks,
        [string]$KeyPath,
        [switch]$Sign
    )
    $PropPaths | ForEach-Object {
        Write-Column "Name", "Value"
        Initialize-Version $_ $Frameworks
        Initialize-Sign -ProjectPath $_ -KeyPath $KeyPath -Sign:$Sign
        Write-Log
    }
}

function Step-ResolveSolution {
    param(
        [string]$SolutionPath
    )
    if ([environment]::OSVersion.Platform -eq "Win32NT") {
        Start-Log
        Write-Log "there is no problems to resolve."
        Stop-Log
    }
    else {
        $projectPaths = Get-ProjectPaths $SolutionPath
        $projectPaths | ForEach-Object {
            $projectType = Get-ProjectType $_
            if ($projectType -eq "Microsoft.NET.Sdk.WindowsDesktop") {
                Invoke-Expression "dotnet sln `"$SolutionPath`" remove `"$_`""
                Write-Log $_ -LogType "Warning" -Label "The project cannot be built on the current platform."
                Write-Log
            }
        }
    }
}

function Step-Result {
    param(
        [datetime]$DateTime
    )
    Start-Log
    if ($LastExitCode -eq 0) {
        $lastTime = Get-Date
        $timeSpan = $lastTime - $DateTime
        Write-Log "Start Time  : $($DateTime.ToString())"
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
        [object]$Message = "",
        [ValidateSet('Output', 'Error', 'Warning')]
        [string]$LogType = "Output",
        [string]$Label = ""
    )
    $text = ""
    if ($Message -is [array]) {
        $text = $Message -join "`n"
    }
    else {
        $text = "$Message"
    }
    switch ($LogType) {
        "Output" { Write-Host $text }
        "Error" { Write-Error -Message $text }
        "Warning" { Write-Warning -Message $text }
    }
    if ($Label -ne "") {
        switch ($LogType) {
            "Output" { Add-Content -Path $LogPath -Value $Label }
            "Error" { Add-Content -Path $LogPath -Value "<span style=`"color:red`">$Label</span>" }
            "Warning" { Add-Content -Path $LogPath -Value "<span style=`"color:yellow`">$Label</span>" }
        }
        Add-Content -Path $LogPath -Value ""
        Add-Content -Path $LogPath -Value "``````plain"
    }
    Add-Content -Path $LogPath -Value $text
    if ($Label -ne "") {
        Add-Content -Path $LogPath -Value "``````"
        Add-Content -Path $LogPath -Value ""
    }
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
    $title = "| $($Columns -join " | ") |"
    $separator = "| $($items) |"
    Add-Content -Path $LogPath -Value $title, $separator
}

function Write-Property {
    param(
        [string]$Name,
        [string[]]$Values
    )
    if ($Values.Length -eq 1) {
        Write-Host "$($Name): $($Values[0])"
        Add-Content -Path $LogPath -Value "| $Name | $($Values[0]) |"
    }
    else {
        Write-Host "$($Name):"
        $Values | ForEach-Object { Write-Host "    $_" }
        Add-Content -Path $LogPath -Value "| $Name | $($Values -join "<br>") |"
    }
}

$token = New-Guid
$platform = $PSVersionTable.Platform
$SolutionPath = Resolve-Path $SolutionPath
$repositoryPaths = Get-RepositoryPaths $SolutionPath

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
    $WorkingPath = Split-Path $SolutionPath
    $PropPaths = Resolve-Path $PropPaths
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
    Write-Property "PropPaths" $PropPaths
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
    Step-RepositoryChanges $repositoryPaths -Force:$Force
    Write-Log

    # save repositories if there is any changes.
    Write-Header "Save repositories"
    Step-SaveRepositories $SolutionPath $token -Force:$Force
    Write-Log

    # recored version and keypath to props file
    Write-Header "Set Information to props files"
    Step-ResolveProp $PropPaths -Frameworks $frameworks -KeyPath $KeyPath -Sign:$Sign
    Write-Log

    # resolve solution
    Write-Header "Resolve Solution"
    Step-ResolveSolution $SolutionPath
    Write-Log
 
    # build project
    Write-Header "Build"
    Step-Build -SolutionPath $SolutionPath -Framework $frameworkOption -Task $Task
    Write-Log

    # record build result
    Write-Header "Result"
    Step-Result -DateTime $dateTime
    Write-Log
}
finally {
    Restore-Repositories $SolutionPath $token -Force:$Force
    Set-Location $location
}
