param(
    [string]$OutputPath = "bin",
    [string]$Framework = "netcoreapp3.1",
    [string]$KeyPath = "",
    [string]$LogPath = "",
    [switch]$Force
)

$OutputPath = Resolve-Path $OutputPath
$location = Get-Location
try {
    Set-Location $PSScriptRoot
    $buildFile = "./build.ps1"
    $propsPath = (
        "./font-generator/JSSoft.Library/Directory.Build.props",
        "./font-generator/JSSoft.Library.Commands/Directory.Build.props",
        "./font-generator/JSSoft.ModernUI.Framework/Directory.Build.props",
        "./font-generator/JSSoft.Fonts/Directory.Build.props"
    ) | ForEach-Object { Resolve-Path $_ }
    $solutionPath = "./font-generator/font-generator.sln"
    if (!(Test-Path $OutputPath)) {
        New-Item $OutputPath -ItemType Directory
    }
    & $buildFile $solutionPath $propsPath -Publish -KeyPath $KeyPath -Sign -OutputPath $OutputPath -Framework $Framework -LogPath $LogPath -Force:$Force
}
finally {
    Set-Location $location
}
