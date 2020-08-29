$location = Get-Location
try {
    Set-Location $PSScriptRoot
    $propsPath = (
        "..\JSSoft.Communication\Directory.Build.props",
        "..\JSSoft.Library\Directory.Build.props",
        "..\JSSoft.Library.Commands\Directory.Build.props",
        "..\JSSoft.ModernUI.Framework\Directory.Build.props",
        "..\JSSoft.Crema\Directory.Build.props"
    ) | ForEach-Object { "`"$_`"" }
    $propsPath = $propsPath -join ","
    $solutionPath = "..\JSSoft.Crema\crema.sln"
    Invoke-Expression ".\build.ps1 $solutionPath $propsPath $args"
}
finally {
    Set-Location $location
}
