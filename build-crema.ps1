param(
    [string]$OutputPath = "",
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

$buildFile = "./build.ps1"
$solutionPath = Join-Path $PSScriptRoot $solutionPath -Resolve
$propPaths = $propPaths | ForEach-Object { Join-Path $PSScriptRoot $_ -Resolve }
& $buildFile $solutionPath $propPaths -Publish -KeyPath $KeyPath -Sign -OutputPath $OutputPath -Framework $Framework -LogPath $LogPath -Force:$Force
