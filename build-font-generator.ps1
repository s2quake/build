param(
    [string]$OutputPath = "",
    [string]$Framework = "netcoreapp3.1",
    [string]$KeyPath = "",
    [string]$LogPath = "",
    [switch]$Force
)

$solutionPath = "./font-generator/font-generator.sln"
$propPaths = (
    "./font-generator/JSSoft.Library/Directory.Build.props",
    "./font-generator/JSSoft.Library.Commands/Directory.Build.props",
    "./font-generator/JSSoft.ModernUI.Framework/Directory.Build.props",
    "./font-generator/JSSoft.Fonts/Directory.Build.props"
)

$buildFile = "./build.ps1"
$solutionPath = Join-Path $PSScriptRoot $solutionPath -Resolve
$propPaths = $propPaths | ForEach-Object { Join-Path $PSScriptRoot $_ -Resolve }
& $buildFile $solutionPath $propPaths -Publish -KeyPath $KeyPath -Sign -OutputPath $OutputPath -Framework $Framework -LogPath $LogPath -Force:$Force
