$location = Get-Location
try {
    Set-Location $PSScriptRoot
    # $keyPath = Resolve-Path (Join-Path $PSScriptRoot "public.snk")
    $keyPath = "/Users/s2quake-mac/OneDrive/문서/private.snk"
    $items = (
        "/Users/s2quake-mac/Projects/crema/JSSoft.Communication/Directory.Build.props",
        "/Users/s2quake-mac/Projects/crema/JSSoft.Library/Directory.Build.props",
        "/Users/s2quake-mac/Projects/crema/JSSoft.Library.Commands/Directory.Build.props",
        "/Users/s2quake-mac/Projects/crema/JSSoft.ModernUI.Framework/Directory.Build.props",
        "/Users/s2quake-mac/Projects/crema/JSSoft.Crema/Directory.Build.props"
    )
    $solutionPath = "/Users/s2quake-mac/Projects/crema/crema.sln"
    .\build.ps1 -SolutionPath $solutionPath -PropsPath $items -AssemblyOriginatorKeyFile $keyPath
}
finally {
    Set-Location $location
}
