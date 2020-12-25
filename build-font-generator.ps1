$location = Get-Location
try {
    Set-Location $PSScriptRoot
    $buildFile = "./build.ps1"
    $outputPath = "bin"
    if (!(Test-Path $outputPath)) {
        New-Item $outputPath -ItemType Directory
    }
    $propsPath = (
        "./font-generator/JSSoft.Library/Directory.Build.props",
        "./font-generator/JSSoft.Library.Commands/Directory.Build.props",
        "./font-generator/JSSoft.ModernUI.Framework/Directory.Build.props",
        "./font-generator/JSSoft.Fonts/Directory.Build.props"
    ) | ForEach-Object { "`"$_`"" }
    $solutionPath = "./font-generator/font-generator.sln"
    $propsPath = $propsPath -join ","
    Invoke-Expression "$buildFile $solutionPath $propsPath -Publish -OutputPath bin $args"
}
finally {
    Set-Location $location
}
