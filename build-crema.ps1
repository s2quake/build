param(
    [string]$OutputPath = "bin",
    [string]$Framework = "netcoreapp3.1",
    [string]$KeyPath = "",
    [string]$LogPath = "",
    [switch]$Force
)

$location = Get-Location
try {
    Set-Location $PSScriptRoot
    $buildFile = "./build.ps1"
    $propsPath = (
        "./crema/JSSoft.Communication/Directory.Build.props",
        "./crema/JSSoft.Library/Directory.Build.props",
        "./crema/JSSoft.Library.Commands/Directory.Build.props",
        "./crema/JSSoft.ModernUI.Framework/Directory.Build.props",
        "./crema/JSSoft.Crema/Directory.Build.props"
    ) | ForEach-Object { Resolve-Path $_ }
    $solutionPath = "./crema/crema.sln"
    if (!(Test-Path $outputPath)) {
        New-Item $outputPath -ItemType Directory
    }
    & $buildFile $solutionPath $propsPath -Publish -KeyPath $KeyPath -Sign -OutputPath $OutputPath -Framework $Framework -LogPath $LogPath -Force:$Force
}
finally {
    Set-Location $location
}
