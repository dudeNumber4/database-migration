# set current dir to this project root.
Set-Location (Get-Item $PSCommandPath).Directory.FullName

$databaseProjectPowershellScriptPath = '..\MigrationDatabase'
$currentProjectPath = './DatabaseMigration.csproj'
$archiveFileName = 'DatabaseMigrationDeliverables.zip'
$archivePath = "./$archiveFileName"  # root of this project

<#
.DESCRIPTION
# Bundles deliverables and leaves the zip at the root of this current project.
#>
function CreateArchive {
    try {
        if (Test-Path $archivePath) {
            Remove-Item $archivePath
        }
	    Compress-Archive `
        -Path "$databaseProjectPowershellScriptPath\*.ps1","$databaseProjectPowershellScriptPath\*.psm1","$databaseProjectPowershellScriptPath\UpdateProject.scmp","./NugetScripts/*.ps1","./NugetScripts/*.psm1","..\GitHooks",".\DatabaseMigration\RuntimeScripts\1.sql","..\README.md" `
        -DestinationPath $archivePath
    }
    catch {
        Write-Host "Error creating compressed content [$archiveFileName] out of project [$databaseProjectPowershellScriptPath]: $_"
	    exit 1
    }
}

<#
.DESCRIPTION
Returns true if the item already exists.
#>
function ItemExists {
    $node = $doc.SelectSingleNode("descendant::ItemGroup/Content[@Include='$archiveFileName']")
    ($null -ne $node)
}

<#
.DESCRIPTION
Get the first ItemGroup element in the given project.
#>
function GetItemGroup([System.Xml.XmlDocument] $doc) {
    $nodes = $doc.SelectNodes("descendant::ItemGroup")
    if ($nodes.Count -ge 0) {
        $nodes[0]
    } else {
        $null
    }
}

<#
.DESCRIPTION
Add the file path as content to the ItemGroup element passed in.  Assumes it's not already there.
#>
function AddFileRefAsContent([System.Xml.XmlElement] $itemGroup) {
    # <Content Include="path">
        # <CopyToOutputDirectory>PreserveNewest<>
    $contentElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'Content', [System.string]::Empty)
    $includeAttr = $doc.CreateAttribute('Include')
    $includeAttr.Value = $archiveFileName
    $contentElem.Attributes.Append($includeAttr) > $null

    $copyElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'CopyToOutputDirectory', [System.string]::Empty)
    $copyElem.InnerText = 'PreserveNewest'
    $contentElem.AppendChild($copyElem) > $null

    $itemGroup.AppendChild($contentElem) > $null
}

<#
.DESCRIPTION
Add zip file as content to the current project.
#>
function AddArchiveToContent {
    $doc = New-Object -TypeName 'System.Xml.XmlDocument'
    $doc.Load($currentProjectPath)
    $exists = ItemExists $archiveFileName
    if (-not $exists) {
        $itemGroup = GetItemGroup $doc
        if ($null -eq $itemGroup) {
            throw "Item group not found in project."
        } else {
            AddFileRefAsContent $itemGroup
            $doc.Save($currentProjectPath) > $null
        }
    }
}

CreateArchive # no handling; let error raise.
AddArchiveToContent
