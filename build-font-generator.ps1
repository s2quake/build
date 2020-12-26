param(
    [string]$OutputPath = "",
    [string]$Framework = "netcoreapp3.1",
    [string]$KeyPath = "",
    [string]$LogPath = "",
    [switch]$Force
)

$solutionPath = "$PSScriptRoot/font-generator/font-generator.sln"
$buildFile = "./build.ps1"
& $buildFile $solutionPath -Publish -KeyPath $KeyPath -Sign -OutputPath $OutputPath -Framework $Framework -LogPath $LogPath -Force:$Force
