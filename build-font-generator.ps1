param(
    [switch]$Help
)
$location = Get-Location
try {
    Set-Location $PSScriptRoot
    $buildFile = "./build.ps1"
    if ($Help) {
        Invoke-Expression "Get-Help $buildFile -Detailed"
    }
    else {
        $propsPath = (
            "./font-generator/JSSoft.Library/Directory.Build.props",
            "./font-generator/JSSoft.Library.Commands/Directory.Build.props",
            "./font-generator/JSSoft.ModernUI.Framework/Directory.Build.props",
            "./font-generator/JSSoft.Fonts/Directory.Build.props"
        ) | ForEach-Object { "`"$_`"" }
        $solutionPath = "./font-generator/font-generator.sln"
        $propsPath = $propsPath -join ","
        Invoke-Expression "$buildFile $solutionPath $propsPath $args"
    }
}
finally {
    Set-Location $location
}
