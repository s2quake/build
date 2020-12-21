$location = Get-Location
try {
    Set-Location $PSScriptRoot
    $propsPath = (
        "./crema/JSSoft.Communication/Directory.Build.props",
        "./crema/JSSoft.Library/Directory.Build.props",
        "./crema/JSSoft.Library.Commands/Directory.Build.props",
        "./crema/JSSoft.ModernUI.Framework/Directory.Build.props",
        "./crema/JSSoft.Crema/Directory.Build.props"
    ) | ForEach-Object { "`"$_`"" }
    $solutionPath = "./crema/crema.sln"
    $propsPath = $propsPath -join ","
    Invoke-Expression "./build.ps1 $solutionPath $propsPath $args"
}
finally {
    Set-Location $location
}
