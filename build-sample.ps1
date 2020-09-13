$location = Get-Location
try {
    Set-Location $PSScriptRoot
    $propsPath = (
        "../communication/JSSoft.Library/Directory.Build.props",
        "../communication/JSSoft.Library.Commands/Directory.Build.props",
        "../communication/JSSoft.Communication/Directory.Build.props"
    ) | ForEach-Object { "`"$_`"" }
    $propsPath = $propsPath -join ","
    $solutionPath = "../communication/communication.sln"
    Invoke-Expression "./build.ps1 $solutionPath $propsPath $args"
}
finally {
    Set-Location $location
}
