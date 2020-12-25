param(
    [switch]$Help
)

$location = Get-Location
try {
    Set-Location $PSScriptRoot
    $buildFile = "./build.ps1"
    if ($Help) {
        Invoke-Expression "Get-Help $buildFile"
    }
    else {
        $propsPath = (
            "./crema/JSSoft.Communication/Directory.Build.props",
            "./crema/JSSoft.Library/Directory.Build.props",
            "./crema/JSSoft.Library.Commands/Directory.Build.props",
            "./crema/JSSoft.ModernUI.Framework/Directory.Build.props",
            "./crema/JSSoft.Crema/Directory.Build.props"
        ) | ForEach-Object { "`"$_`"" }
        $solutionPath = "./crema/crema.sln"
        $propsPath = $propsPath -join ","
        Invoke-Expression "$buildFile $solutionPath $propsPath $args"
    }
}
finally {
    Set-Location $location
}
