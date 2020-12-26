<#
    .SYNOPSIS
        빌드
    .DESCRIPTION
        build description,
    .PARAMETER SolutionPath
        test description for SolutionPath
        
#>
[CmdletBinding(DefaultParameterSetName = 'Build')]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Build", Position = 0)]
    [Parameter(Mandatory = $true, ParameterSetName = "Publish", Position = 0)]
    [Parameter(Mandatory = $true, ParameterSetName = "Pack", Position = 0)]
    [string]$SolutionPath,

    [Parameter(Mandatory = $true, ParameterSetName = "Build", Position = 1)]
    [Parameter(Mandatory = $true, ParameterSetName = "Publish", Position = 1)]
    [Parameter(Mandatory = $true, ParameterSetName = "Pack", Position = 1)]
    [string[]]$PropPaths,

    [Parameter(ParameterSetName = "Build")]
    [ValidateSet("build", "publish", "pack")]
    [string]$Task = "build",

    [Parameter(ParameterSetName = "Publish", Position = 2)]
    [switch]$Publish,

    [Parameter(ParameterSetName = "Pack", Position = 2)]
    [switch]$Pack,

    [Parameter(ParameterSetName = "Build")]
    [Parameter(ParameterSetName = "Publish")]
    [Parameter(ParameterSetName = "Pack")]
    [string]$KeyPath = "",

    [Parameter(ParameterSetName = "Build")]
    [Parameter(ParameterSetName = "Publish")]
    [Parameter(ParameterSetName = "Pack")]
    [string]$LogPath = "",

    [Parameter(ParameterSetName = "Build")]
    [string]$Configuration = "Release",

    [Parameter(ParameterSetName = "Build")]
    [Parameter(ParameterSetName = "Publish")]
    [string]$Framework = "netcoreapp3.1",

    [Parameter(ParameterSetName = "Build")]
    [Parameter(ParameterSetName = "Publish")]
    [Parameter(ParameterSetName = "Pack")]
    [string]$OutputPath = "",

    [Parameter(ParameterSetName = "Build")]
    [Parameter(ParameterSetName = "Publish")]
    [Parameter(ParameterSetName = "Pack")]
    [switch]$Sign,

    [Parameter(ParameterSetName = "Build")]
    [switch]$OmitSymbol,

    [Parameter(ParameterSetName = "Build")]
    [Parameter(ParameterSetName = "Publish")]
    [Parameter(ParameterSetName = "Pack")]
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
    param(
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

function Backup-Files {
    param(
        [string[]]$FilePaths
    )
    $FilePaths | ForEach-Object {
        $path = "$_.bak";
        Copy-Item $_ $path
    }
}

function Restore-Files {
    param(
        [string[]]$FilePaths
    )
    $FilePaths | ForEach-Object {
        $path = "$_.bak";
        if (Test-Path $path) {
            Copy-Item $path $_ -Force
            Remove-Item $path
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
    param(
        [string]$ProjectPath,
        [string]$Framework
    )
    try {
        $revision = Get-Revision $ProjectPath
        [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
        if ($null -eq $doc.Project.PropertyGroup.FileVersion) {
            throw "there is no version"
        }
        $version = "$($doc.Project.PropertyGroup.FileVersion)-`$(TargetFramework)-$revision"
        $versionText = "$($doc.Project.PropertyGroup.FileVersion)-$Framework-$revision"
        $doc.Project.PropertyGroup.Version = $version
        $doc.Save($ProjectPath)
        
        Write-Property "Path" $ProjectPath
        Write-Property "Version" $versionText
    }
    catch {
        Write-Log $_.Exception.Message -LogType "Error"
        exit 1
    }
}

function Initialize-Sign {
    param(
        [string]$ProjectPath,
        [string]$KeyPath,
        [switch]$Sign
    )
    [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
    $propertyGroupNode = $doc.CreateElement("PropertyGroup", $doc.DocumentElement.NamespaceURI)
    $delaySign = ("" -eq $KeyPath) -and ($true -eq $Sign);
    $signAssembly = $Sign;

    $node = $doc.CreateElement("DelaySign", $doc.DocumentElement.NamespaceURI)
    if ($true -eq $delaySign) {
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

function Resolve-LogPath {
    param(
        [string]$LogPath,
        [datetime]$DateTime
    )
    if (!$LogPath) {
        $dateTimeText = $DateTime.ToString("yyyy-MM-dd_hh-mm-ss")
        $logDirectory = Join-Path (Get-Location) "logs"
        if (!(Test-Path $logDirectory)) {
            New-Item $logDirectory -ItemType Directory -ErrorAction Stop
        }
        $LogPath = Join-Path $logDirectory "$($dateTimeText).md"
    }
    Set-Content $LogPath "" -Encoding UTF8 -ErrorAction Stop
    return $LogPath
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
            Write-Log
        }
    }
    finally {
    }
}

function Step-SaveRepositories {
    param(
        [string]$SolutionPath,
        [guid]$Token,
        [switch]$Force
    )
    $items = Get-RepositoryPaths $SolutionPath
    if ($Force) {
        $items | Sort-Object -Descending | ForEach-Object {
            Invoke-Expression "git -C `"$_`" stash save -q --message `"$Token`""
            $stash = Test-Stash $_ $Token
            if ($stash) {
                Invoke-Expression "git -C `"$_`" stash apply $stash --index -q"
            }
        }
    }
}

function Step-Build {
    param(
        [string]$SolutionPath,
        [ValidateSet('build', 'publish', 'pack')]
        [string]$Task = "build",
        [string]$Framework,
        [string]$Configuration,
        [string]$OutputPath,
        [switch]$OmitSymbol
    )
    [string[]]$resultItems = $()
    $frameworkOption = ""
    $configurationOption = "--configuration Release"
    $outputOption = ""
    $symbolOption = ""
    if ($Framework) {
        $frameworkOption = "--framework $Framework"
    }
    if ($Configuration) {
        $configurationOption = "--configuration $Configuration"
    }
    if ($OutputPath) {
        $outputOption = "--output `"$OutputPath`""
    }
    if ($OmitSymbol) {
        $symbolOption = "-p:DebugType=None -p:DebugSymbols=false"
    }
    # --verbosity quiet --nologo 
    $expression = "dotnet $Task `"$SolutionPath`" $frameworkOption $configurationOption --verbosity m $outputOption $symbolOption"
    Invoke-Expression $expression | Tee-Object -Variable items | ForEach-Object {
        $pattern1 = "^(?:\s+\d+\>)?([^\s].*)\((\d+|\d+,\d+|\d+,\d+,\d+,\d+)\)\s*:\s+(error|warning|info)\s+(\w{1,2}\d+)\s*:\s*(.+)\[(.+)\]$"
        $pattern2 = "^(.+)\s*:\s+(error|warning|info)\s+(\w{1,2}\d+)\s*:\s*(.+)\[(.+)\]$"
        if ($_ -match $pattern1) {
            $values = @{};
            $values["Path"] = $Matches[1]
            $values["Location"] = $Matches[2]
            $values["Type"] = $Matches[3]
            $values["TypeValue"] = $Matches[4]
            $values["Message"] = $Matches[5]
            $values["Project"] = $Matches[6]
            Write-BuildError $values $_
        }
        elseif ($_ -match $pattern2) {
            $values = @{};
            $values["Path"] = $Matches[1]
            $values["Type"] = $Matches[2]
            $values["TypeValue"] = $Matches[3]
            $values["Message"] = $Matches[4]
            $values["Project"] = $Matches[5]
            Write-BuildError $values $_
        }
        else {
            $resultItems += $_
        }
    }

    Start-Log
    Write-Log $resultItems
    Stop-Log
    Write-Log
}

function Step-ResolveProp {
    param(
        [string[]]$PropPaths,
        [string]$Framework,
        [string]$KeyPath,
        [switch]$Sign
    )
    $PropPaths | ForEach-Object {
        Write-Column "Name", "Value"
        Initialize-Version -ProjectPath $_ -Framework $Framework
        Initialize-Sign -ProjectPath $_ -KeyPath $KeyPath -Sign:$Sign
        Write-Log
    }
}

function Step-ResolveSolution {
    param(
        [string]$SolutionPath
    )
    $isModified = $false
    if ([environment]::OSVersion.Platform -ne "Win32NT") {
        $projectPaths = Get-ProjectPaths $SolutionPath
        $projectPaths | ForEach-Object {
            $projectType = Get-ProjectType $_
            if ($projectType -eq "Microsoft.NET.Sdk.WindowsDesktop") {
                Invoke-Expression "dotnet sln `"$SolutionPath`" remove `"$_`""
                Write-Log $_ -LogType "Warning" -Label "The project cannot be built on the current platform."
            }
        }
    }
    if ($isModified) {
        Start-Log
        Write-Log "there is no problems to resolve."
        Stop-Log
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
        Write-Host "LogPath     : $LogPath"
        if ($OutputPath) {
            Write-Host "OutputPath  : $OutputPath"
        }
        Write-Log "build completed."
    }
    else {
        Write-Host "LogPath: $LogPath"
        Write-Log "build failed" -LogType "Error"
    }
    Stop-Log
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
        [string[]]$Values,
        [switch]$OmitLog
    )
    if ($Values.Length -eq 1) {
        if (!$OmitLog) {
            Write-Host "$($Name): $($Values[0])"
        }
        Add-Content -Path $LogPath -Value "| $Name | $($Values[0]) |"
    }
    else {
        if (!$OmitLog) {
            Write-Host "$($Name):"
            $Values | ForEach-Object { Write-Host "    $_" }
        }
        Add-Content -Path $LogPath -Value "| $Name | $($Values -join "<br>") |"
    }
}

function Write-BuildError {
    param(
        [hashtable]$Table,
        [string]$FullText
    )

    $path = $Table["Path"];
    $location = $Table["Location"];
    $type = $Table["Type"];
    $typeValue = $Table["TypeValue"];
    $message = $Table["Message"];
    $project = $Table["Project"];

    Write-Column "Name", "Value"
    switch ($type) {
        "error" {
            Write-Error -Message $FullText
            Write-Property "Error" "<span style=`"color:red`">$typeValue</span>" -OmitLog
        }
        "warning" {
            Write-Warning -Message $FullText
            Write-Property "Warning" "<span style=`"color:yellow`">$typeValue</span>" -OmitLog
        }
        "info" {
            Write-Information -MessageData $FullText
            Write-Property "Information" $typeValue
        }
    }
    Write-Property "Path" $path -OmitLog
    if ($location) {
        Write-Property "Location" $location -OmitLog
    }
    Write-Property "Message" $message -OmitLog
    Write-Property "Project" $project -OmitLog
    Write-Log "________________________________________________________________________________"
}

$location = Get-Location
try {
    $dateTime = Get-Date
    # if (!$LogPath) {
    #     $dateTimeText = $dateTime.ToString("yyyy-MM-dd_hh-mm-ss")
    #     $logDirectory = Join-Path (Get-Location) "logs"
    #     if (!(Test-Path $logDirectory)) {
    #         New-Item $logDirectory -ItemType Directory -ErrorAction Stop
    #     }
    #     $LogPath = Join-Path $logDirectory "$($dateTimeText).md"
    # }
    # Set-Content $LogPath "" -Encoding UTF8 -ErrorAction Stop
    $LogPath = Resolve-LogPath $LogPath $dateTime

    # initialize
    Write-Header "Initialize"

    $SolutionPath = Resolve-Path $SolutionPath -ErrorAction Stop
    $PropPaths = Resolve-Path $PropPaths -ErrorAction Stop
    if ($OutputPath) {
        $OutputPath = Resolve-Path $OutputPath -ErrorAction Stop
    }
    if ($KeyPath) {
        $KeyPath = Resolve-Path $KeyPath -ErrorAction Stop
    }

    if ($Publish) {
        $Configuration = "Release"
        $OmitSymbol = $true
        $Task = "publish"

        if (!$OutputPath) {
            $OutputPath = Join-Path (Split-Path $SolutionPath) "bin" -ErrorAction Stop
        }
        if (!(Test-Path $OutputPath)) {
            New-Item $OutputPath -ItemType Directory -ErrorAction Stop
        } 
        $OutputPath = Resolve-Path $OutputPath
    }
    elseif ($Pack) {
        $Configuration = "Release"
        $Framework = ""
        $OmitSymbol = $true
        $Task = "pack"
        if (!$OutputPath) {
            $OutputPath = Join-Path (Split-Path $SolutionPath) "pack" -ErrorAction Stop
        }
        if (!(Test-Path $OutputPath)) {
            New-Item $OutputPath -ItemType Directory -ErrorAction Stop
        } 
    }
    
    Write-Column "Name", "Value"
    Write-Property "DateTime" $dateTime.ToString()
    Write-Property "SolutionPath" $SolutionPath
    Write-Property "WorkingPath" (Split-Path $SolutionPath)
    for ($i = 0 ; $i -lt $PropPaths.Length; $i++) {
        Write-Property "PropPaths: $i" $PropPaths[$i]
    }
    Write-Property "Task" $Task
    Write-Property "Framework" $Framework
    Write-Property "Configuration" $Configuration
    Write-Property "OutputPath" $OutputPath
    Write-Property "KeyPath" $KeyPath
    Write-Property "OmitSign" $OmitSign
    Write-Property "Force" $Force
    Write-Log

    $repositoryPaths = Get-RepositoryPaths $SolutionPath

    # check if there are any changes in the repository.
    Write-Header "Repository changes"
    Step-RepositoryChanges -RepositoryPaths $repositoryPaths -Force:$Force
    Backup-Files -FilePaths $PropPaths
    Backup-Files -FilePaths $SolutionPath

    # recored version and keypath to props file
    Write-Header "Set Information to props files"
    Step-ResolveProp -PropPaths $PropPaths -Framework $Framework -KeyPath $KeyPath -Sign:$Sign

    # resolve solution
    Write-Header "Resolve Solution"
    Step-ResolveSolution -SolutionPath $SolutionPath
 
    # build project
    Write-Header "Build"
    Step-Build -SolutionPath $SolutionPath -Task $Task -Framework $Framework -Configuration $Configuration -OutputPath $OutputPath -OmitSymbol:$OmitSymbol

    # record build result
    Write-Header "Result"
    Step-Result -DateTime $dateTime
}
finally {
    Restore-Files -FilePaths $PropPaths
    Restore-Files -FilePaths $SolutionPath
    Set-Location $location
}
