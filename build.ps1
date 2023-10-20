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
    [string]$Framework = "",

    [Parameter(ParameterSetName = "Build")]
    [Parameter(ParameterSetName = "Publish")]
    [Parameter(ParameterSetName = "Pack")]
    [string]$OutputPath = "",

    [Parameter(ParameterSetName = "Build")]
    [Parameter(ParameterSetName = "Publish")]
    [Parameter(ParameterSetName = "Pack")]
    [switch]$Sign,

    [Parameter(ParameterSetName = "Build")]
    [switch]$OmitSymbol
)

function Resolve-LogPath {
    param(
        [string]$LogPath,
        [datetime]$DateTime,
        [string]$SolutionPath
    )
    if (!$LogPath) {
        $dateTimeText = $DateTime.ToString("yyyy-MM-dd_hh-mm-ss")
        $logDirectory = Join-Path (Get-Location) "logs"
        $name = (Get-Item $SolutionPath).BaseName
        if (!(Test-Path $logDirectory)) {
            $logDirectory = New-Item $logDirectory -ItemType Directory -ErrorAction Stop
        }
        $LogPath = Join-Path $logDirectory "$name-$($dateTimeText).md"
    }
    Set-Content $LogPath "" -Encoding UTF8 -ErrorAction Stop
    return $LogPath
}

function Step-Build {
    $delaySign = ("" -eq $KeyPath) -and ($true -eq $Sign)
    $options = @(
        $Task
        $Framework ? "--framework $Framework" : ""
        $Configuration ? "--configuration $Configuration": "--configuration Release"
        $OutputPath ? "--output `"$OutputPath`"" : ""
        $OmitSymbol ? "-p:DebugType=None" : ""
        $OmitSymbol ? "-p:DebugSymbols=false" : ""
        $delaySign ? "-p:DelaySign=true" : "-p:DelaySign=false"
        $Sign ? "-p:SignAssembly=true" : "-p:SignAssembly=false"
        $KeyPath ? "-p:AssemblyOriginatorKeyFile='$KeyPath'" : ""
        "--verbosity m"
    ) | Where-Object { $_ } | Join-String -Separator " "
    $expression = "dotnet $options"
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
        Write-Log $_
    }

    Write-Log
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
    $LogPath = Resolve-LogPath $LogPath $dateTime $SolutionPath

    # initialize
    Write-Header "Initialize"

    $SolutionPath = Resolve-Path $SolutionPath -ErrorAction Stop
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
    Write-Property "Task" $Task
    Write-Property "Framework" $Framework
    Write-Property "Configuration" $Configuration
    Write-Property "OutputPath" $OutputPath
    Write-Property "KeyPath" $KeyPath
    Write-Property "Sign" $Sign
    Write-Log

    # build project
    Write-Header "Build"
    Step-Build -SolutionPath $SolutionPath -Task $Task -Framework $Framework -Configuration $Configuration -OutputPath $OutputPath -OmitSymbol:$OmitSymbol

    # record build result
    Write-Header "Result"
    Step-Result -DateTime $dateTime
}
finally {
    Set-Location $location
}
