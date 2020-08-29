function Initialize-Target {
    param (
        [string]$ProjectPath
    )
    [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
    if (!(Select-Xml -Xml $doc -XPath "/Project/Target[@Name='GetFileVersion']")) {
        $targetNode = $doc.CreateElement("Target")
        $nameAttr = $targetNode.OwnerDocument.CreateAttribute("Name")
        $nameAttr.Value = "GetFileVersion"
        $targetNode.Attributes.Append($nameAttr) | Out-Null
        $doc.Project.AppendChild($targetNode) | Out-Null
        
        $messageNode = $doc.CreateElement("Message")
        $textAttr = $messageNode.OwnerDocument.CreateAttribute("Text")
        $textAttr.Value = "`$(FileVersion)"
        $importanceAttr = $messageNode.OwnerDocument.CreateAttribute("Importance")
        $importanceAttr.Value = "high"
        $messageNode.Attributes.Append($textAttr) | Out-Null
        $messageNode.Attributes.Append($importanceAttr) | Out-Null
        $targetNode.AppendChild($messageNode) | Out-Null
        $doc.Save($ProjectPath)
    }
}

function Initialize-Sign {
    param (
        [string]$ProjectPath,
        [string]$KeyPath

    )
    [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
    $propertyGroupNode = $doc.CreateElement("PropertyGroup")
        $node = $doc.CreateElement("DelaySign")
        $text = $doc.CreateTextNode("false")
        $node.AppendChild($text) | Out-Null
        
        $propertyGroupNode.AppendChild($node) | Out-Null
        $node = $doc.CreateElement("SignAssembly")
        $text = $doc.CreateTextNode("true")
        $node.AppendChild($text) | Out-Null
        $propertyGroupNode.AppendChild($node) | Out-Null

        $node = $doc.CreateElement("AssemblyOriginatorKeyFile")
        $text = $doc.CreateTextNode($KeyPath)
        $node.AppendChild($text) | Out-Null
        $propertyGroupNode.AppendChild($node) | Out-Null
    $doc.Project.AppendChild($propertyGroupNode) | Out-Null
    $doc.Save($ProjectPath)
}

function Initialize-Version {
    param (
        [string]$ProjectPath,
        [string]$Version
    )
    [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
    $propertyGroupNode = $doc.CreateElement("PropertyGroup")
    $doc.Project.AppendChild($propertyGroupNode) | Out-Null
        
    $versionNode = $doc.CreateElement("Version")
    $versionText = $doc.CreateTextNode($Version)
    $versionNode.AppendChild($versionText) | Out-Null
    $propertyGroupNode.AppendChild($versionNode) | Out-Null
    $doc.Save($ProjectPath)
}

function Get-FileVersion {
    param (
        [string]$ProjectPath
    )
    $version = Invoke-Expression "dotnet msbuild `"$ProjectPath`" -t:GetFileVersion -p:TargetFramework=netcoreapp3.1 -nologo"
    if ($version) {
        $version.Trim()
    }
}

function Get-ProjectPaths {
    param(
        [string]$SolutionPath
    )
    $items = Invoke-Expression "dotnet sln `"$SolutionPath`" list"
    $directory = Split-Path $SolutionPath
    $items | ForEach-Object {
        if ($null -ne $_) {
            $path = Join-Path $directory $_
            if (Test-Path $path) {
                $path
            }
        }
    }
}

function Get-Revision {
    param(
        [string]$Path
    )
    $location = Get-Location
    try {
        if (Test-Path -Path $Path) {
            if (Test-Path -Path $Path -PathType Container) {
                Set-Location -Path $Path
            }
            else {
                Set-Location -Path (Split-Path $Path)
            }
        }
        $revision = Invoke-Expression -Command "git rev-parse HEAD" 2>&1 -ErrorVariable errout
        if ($LastExitCode -ne 0) {
            throw $errout
        }
        return $revision
    }
    catch {
        Write-Error $_.Exception.Message
        return $null
    }
    finally {
        Set-Location $location
    }
}

Export-ModuleMember -Function Initialize-Target, Initialize-Sign, Initialize-Version, Get-FileVersion, Get-ProjectPaths, Get-Revision