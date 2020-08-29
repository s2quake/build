

$path = "./src/ConsoleApp1/ConsoleApp1.csproj"
# [xml]$doc = Get-Content $path -Encoding UTF8
# $doc.Project.PropertyGroup.Version = "$($doc.Project.PropertyGroup.FileVersion)-`$(TargetFramework)-$revision"
# if ("" -eq $AssemblyOriginatorKeyFile) {
#     $doc.Project.PropertyGroup.AssemblyOriginatorKeyFile = $AssemblyOriginatorKeyFile
#     $doc.Project.PropertyGroup.DelaySign = $FALSE
# }

# function Initialize-Target {
#     param (
#         [string]$ProjectPath
#     )
#     [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
#     if (!(Select-Xml -Xml $doc -XPath "/Project/Target[@Name='GetFileVersion']")) {
#         $targetNode = $doc.CreateElement("Target")
#         $nameAttr = $targetNode.OwnerDocument.CreateAttribute("Name")
#         $nameAttr.Value = "GetFileVersion"
#         $targetNode.Attributes.Append($nameAttr) | Out-Null
#         $doc.Project.AppendChild($targetNode) | Out-Null
        
#         $messageNode = $doc.CreateElement("Message")
#         $textAttr = $messageNode.OwnerDocument.CreateAttribute("Text")
#         $textAttr.Value = "`$(FileVersion)"
#         $importanceAttr = $messageNode.OwnerDocument.CreateAttribute("Importance")
#         $importanceAttr.Value = "high"
#         $messageNode.Attributes.Append($textAttr) | Out-Null
#         $messageNode.Attributes.Append($importanceAttr) | Out-Null
#         $targetNode.AppendChild($messageNode) | Out-Null
#         $doc.Save($ProjectPath)
#     }
# }

# function Initialize-Sign {
#     param (
#         [string]$ProjectPath,
#         [string]$KeyPath

#     )
#     [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
#     $propertyGroupNode = $doc.CreateElement("PropertyGroup")
#         $node = $doc.CreateElement("DelaySign")
#         $text = $doc.CreateTextNode("false")
#         $node.AppendChild($text) | Out-Null

#         $propertyGroupNode.AppendChild($node) | Out-Null
#         $node = $doc.CreateElement("SignAssembly")
#         $text = $doc.CreateTextNode("true")
#         $node.AppendChild($text) | Out-Null
#         $propertyGroupNode.AppendChild($node) | Out-Null

#         $node = $doc.CreateElement("AssemblyOriginatorKeyFile")
#         $text = $doc.CreateTextNode($KeyPath)
#         $node.AppendChild($text) | Out-Null
#         $propertyGroupNode.AppendChild($node) | Out-Null
#     $doc.Project.AppendChild($propertyGroupNode) | Out-Null
#     $doc.Save($ProjectPath)
# }

# function Initialize-Version {
#     param (
#         [string]$ProjectPath,
#         [string]$Version
#     )
#     [xml]$doc = Get-Content $ProjectPath -Encoding UTF8
#     $propertyGroupNode = $doc.CreateElement("PropertyGroup")
#     $doc.Project.AppendChild($propertyGroupNode) | Out-Null
        
#     $versionNode = $doc.CreateElement("Version")
#     $versionText = $doc.CreateTextNode($Version)
#     $versionNode.AppendChild($versionText) | Out-Null
#     $propertyGroupNode.AppendChild($versionNode) | Out-Null
#     $doc.Save($ProjectPath)
# }

# function Get-FileVersion {
#     param (
#         [string]$ProjectPath
#     )
#     $version = Invoke-Expression "dotnet msbuild `"$ProjectPath`" -t:GetFileVersion -p:TargetFramework=netcoreapp3.1 -nologo"
#     if ($version) {
#         $version.Trim()
#     }
# }

Import-Module "./build" -Verbose

# Initialize-Target $path
# Get-FileVersion $path
# Initialize-Version $path "7.0.0-wow-ewrwerwer"
# Initialize-Sign $path "/Users/s2quake-mac/OneDrive/문서/private.snk"

$items = Get-ProjectPaths "/Users/s2quake-mac/Projects/crema/crema.sln"

$items | ForEach-Object {
    Initialize-Target $_
    $version = Get-FileVersion $_
    $revion = Get-Revision $_
    Initialize-Version $_ "$version-`$(TargetFramework)-$revion"
    Initialize-Sign $_ "/Users/s2quake-mac/OneDrive/문서/private.snk"
}

Remove-Module "build" -Verbose


# if (!(Select-Xml -Xml $doc -XPath "/Project/Target[@Name='GetVersion']")) {
#     $targetNode = $doc.CreateElement("Target")
#     $nameAttr = $targetNode.OwnerDocument.CreateAttribute("Name")
#     $nameAttr.Value = "GetVersion"
#     $targetNode.Attributes.Append($nameAttr) | Out-Null
#     $doc.Project.AppendChild($targetNode) | Out-Null
    
#     $messageNode = $doc.CreateElement("Message")
#     $textAttr = $messageNode.OwnerDocument.CreateAttribute("Text")
#     $textAttr.Value = "`$(FileVersion)"
#     $importanceAttr = $messageNode.OwnerDocument.CreateAttribute("Importance")
#     $importanceAttr.Value = "high"
#     $messageNode.Attributes.Append($textAttr) | Out-Null
#     $messageNode.Attributes.Append($importanceAttr) | Out-Null
#     $targetNode.AppendChild($messageNode) | Out-Null
    
#     $doc.Save($path)
# }

# dotnet msbuild "$path" -t:GetVersion -p:TargetFramework=netcoreapp3.1 -nologo
