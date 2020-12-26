param(
    [string]$OutputPath = "bin",
    [string]$Framework = "netcoreapp3.1",
    [string]$KeyPath = "",
    [string]$LogPath = "",
    [switch]$Force
)

$solutionPath = "$PSScriptRoot/crema/crema.sln"
$buildFile = "./build.ps1"
& $buildFile $solutionPath -Publish -KeyPath $KeyPath -Sign -OutputPath $OutputPath -Framework $Framework -LogPath $LogPath -Force:$Force
