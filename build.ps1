param(
    [string]$WorkingPath = $PSScriptRoot,
    [string]$SolutionPath = "",
    [string]$PropsPath = (Join-Path $PSScriptRoot "base.props"),
    [switch]$Force
)
$revision = "unversioned"
$frameworkOption = ""
$location = Get-Location

try {
    Set-Location $WorkingPath

    $WorkingPath = Resolve-Path $WorkingPath
    $PropsPath = Resolve-Path $PropsPath
    if ($SolutionPath -ne "") {
        $SolutionPath = Resolve-Path $SolutionPath
    }

    Write-Host "WorkingPath: $WorkingPath"
    Write-Host "PropsPath: $PropsPath"
    Write-Host "SolutionPath: $SolutionPath"
    Write-Host ""
    
    # validate dotnet version
    try {
        [System.Version]$needVersion = "3.1"
        [System.Version]$realVersion = dotnet --version
        if ($realVersion -lt $needVersion) {
            throw "NET Core $needVersion or higher version must be installed to build this project."
        }
    }
    catch {
        Write-Error $_.Exception.Message
        Write-Warning "Please visit the site below and install it."
        Write-Warning "https://dotnet.microsoft.com/download/dotnet-core/$needVersion"
        Write-Host ""
        Write-Host 'Press any key to continue...';
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown');
        exit 1
    }

    # validate .netframework 4.5
    try {
        Invoke-Expression "dotnet msbuild `"$SolutionPath`" -t:GetReferenceAssemblyPaths -v:n -p:TargetFramework=net45" | Out-Null
        if ($LastExitCode -ne 0) {
            throw "Unable to build to .NET Framework 4.5."
        }
    }
    catch {
        Write-Warning $_.Exception.Message
        if ([environment]::OSVersion.Platform -eq "Unix") {
            Write-Warning "To build this project with .NET Framework 4.5, visit site below and install the latest version of mono."
            Write-Warning "https://www.mono-project.com"
        }
        elseif ([environment]::OSVersion.Platform -eq "Win32NT") {
            Write-Warning "To build this project with .NET Framework 4.5, you must install tools and component below."
            Write-Warning "https://visualstudio.microsoft.com/downloads"
            Write-Warning "Install `"Visual Studio 2019 Community`" or `"Build Tools for Visual Studio 2019`""
            Write-Warning "In addition, install the following items on the `"Individual Components`" tab of the `"Visual Studio Installer`"."
            Write-Warning "    .NET Core 3.1 LTS Runtime"
            Write-Warning "    .NET Core SDK"
            Write-Warning "    .NET Framework 4.5 targeting pack"
        }
        Write-Host ""
        $frameworkOption = "--framework netcoreapp3.1"
    }

    # check if there are any changes in the repository.
    try {
        $changes = Invoke-Expression "git status --porcelain"
        if ($changes) {
            throw "git repository has changes. build aborted."
        }
    }
    catch {
        if ($Force -eq $False) {
            Write-Error $_.Exception.Message
            exit 1
        }
    }

    # get head revision of this repository
    try {
        $revision = Invoke-Expression -Command "git rev-parse HEAD" 2>&1 -ErrorVariable errout
        if ($LastExitCode -ne 0) {
            throw $errout
        }
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }

    # recored version to props file
    [xml]$doc = Get-Content $PropsPath -Encoding UTF8
    $doc.Project.PropertyGroup.Version = "$($doc.Project.PropertyGroup.FileVersion)-`$(TargetFramework)-$revision"
    $doc.Save($PropsPath)

    $assemblyVersion = $doc.Project.PropertyGroup.AssemblyVersion
    $fileVersion = $fileVersion

    # build project
    Invoke-Expression "dotnet build `"$SolutionPath`" $frameworkOption --verbosity minimal --nologo"
    if ($LastExitCode -ne 0) {
        Write-Error "build failed"
    }
    else {
        Write-Host ""
        Write-Host "AssemblyVersion: $assemblyVersion"
        Write-Host "FileVersion: $fileVersion"
        Write-Host "revision: $revision"
        Write-Host ""
    }

    # revert props file
    if ($Force -eq $False) {
        Invoke-Expression "git checkout `"$PropsPath`"" 2>&1
    }
}
finally {
    Set-Location $location
}