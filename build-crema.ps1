param(
    [string]$OutputPath = "bin",
    [string]$Framework = "netcoreapp3.1",
    [string]$KeyPath = "",
    [string]$LogPath = "",
    [switch]$Force
)

$solutionPath = "./crema/crema.sln"
$propPaths = (
    "./crema/JSSoft.Communication/Directory.Build.props",
    "./crema/JSSoft.Library/Directory.Build.props",
    "./crema/JSSoft.Library.Commands/Directory.Build.props",
    "./crema/JSSoft.ModernUI.Framework/Directory.Build.props",
    "./crema/JSSoft.Crema/Directory.Build.props"
)

if (!(Test-Path $OutputPath)) {
    New-Item $OutputPath -ItemType Directory
}
$OutputPath = Resolve-Path $OutputPath
$location = Get-Location
$buildFile = "./build.ps1"
try {
    Set-Location $PSScriptRoot
    $propPaths = $propPaths | ForEach-Object { Resolve-Path $_ }
    $solutionPath = Resolve-Path $solutionPath
    & $buildFile $solutionPath $propPaths -Publish -KeyPath $KeyPath -Sign -OutputPath $OutputPath -Framework $Framework -LogPath $LogPath -Force:$Force
}
finally {
    Set-Location $location
}
