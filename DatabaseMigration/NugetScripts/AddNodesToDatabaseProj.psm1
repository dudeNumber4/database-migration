# Database project is still olde school XML
$namespaceURI = 'http://schemas.microsoft.com/developer/msbuild/2003'

<#
.DESCRIPTION
Returns whether the (database) proj file contains the @#@!ing namespace
#>
function ContainsExpectedNamespace([string] $projPath) {
    # like returns array of matches
    ((Get-Content $projPath) -like "*$namespaceURI*").Length -gt 0
}

<#
.DESCRIPTION
Add actual directories that will become solution folders if they don't exist.
#>
function AddDirectory([string] $projPath, [string] $dir) {
    $rootDir = [System.IO.Path]::GetDirectoryName($projPath)
    if (-not [System.IO.Directory]::Exists($rootDir)) {
        throw "Invalid path to project file: $projPath"
    }
    $pos = $dir.IndexOf('\')
    if ($pos -gt 0) {
        $firstDir = $dir.Substring(0, $pos)
        $secondDir = $dir.Substring($pos + 1, $dir.Length - $pos - 1)
        # this is brain-dead; I could've just used mkdir
        $fullFirstDir = [System.IO.path]::Combine($rootDir, $firstDir)
        $fullSecondDir = [System.IO.path]::Combine($rootDir, $firstDir, $secondDir)
        if (($fullFirstDir.Length -gt 0) -and ($fullSecondDir.Length -gt 0)) {
            if (-not [System.IO.Directory]::Exists($fullFirstDir)) {
                Write-Host "Copying directory [$fullFirstDir] into database project" -ForegroundColor Green
                [System.IO.Directory]::CreateDirectory($fullFirstDir) > $null
            }
            if (-not [System.IO.Directory]::Exists($fullSecondDir)) {
                Write-Host "Copying directory [$fullSecondDir] into database project" -ForegroundColor Green
                [System.IO.Directory]::CreateDirectory($fullSecondDir) > $null
            }
        } else {
            throw "Invalid directory parameter: $dir"
        }
    }
}

<#
.DESCRIPTION
Given a (potential) collection of ItemGroup nodes, return the one that has a `childElementName` child.
#>
function GetElementParent([System.Xml.XmlNodeList] $nodes, [string] $childElementName) {
    [System.Xml.XmlElement] $result = $null
    $itemGroupParents = $nodes | Where-Object {
        $_.ChildNodes | Where-Object { $_.Name -eq $childElementName }
    }
    if ($null -eq $itemGroupParents) {
        return
    } elseif ($itemGroupParents -is [Array]) {
        $result = $itemGroupParents[0]
    } elseif ($itemGroupParents -is [System.Xml.XmlElement]) {
        $result = $itemGroupParents
    } else {
        throw 'shouldnt get here'
    }    
    $result
}    

<#
.DESCRIPTION
We've found or created the appropriate parent ItemGroup, append our new $childElemName element referencing our 'Include' elem name if it doesn't exist.
#>
function AppendChildElement([System.Xml.XmlDocument] $doc, [System.Xml.XmlElement] $parent, [string] $childElemName, [string] $includeElemName) {
    $attribName = 'Include'
    # look for <Folder Include="$includeElemName" />
    $existingNodes = $parent.SelectNodes("//x:$childElemName", $ns) | Where-Object {$_.Name -eq $childElemName -and ($_.Attributes | Where-Object { ($_.Name -eq $attribName) -and ($_.Value -eq $includeElemName) } )}
    if ($null -eq $existingNodes) {
        # Not found; add it
        Write-Host "Adding reference [$includeElemName] to database project file." -ForegroundColor Green
        $folderElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, $childElemName, $namespaceURI)
        $folderAttr = $doc.CreateAttribute($attribName)
        $folderAttr.Value = $includeElemName
        $folderElem.Attributes.Append($folderAttr) > $null
        $parent.AppendChild($folderElem) > $null
    }
}

<#
.DESCRIPTION
Append new ItemGroup element and return it.
#>
function AppendItemGroupElement([System.Xml.XmlDocument] $doc, [System.Xml.XmlElement] $parent) {
    $result = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'ItemGroup', $namespaceURI)
    $parent.AppendChild($result) > $null
    $result
}

<#
.DESCRIPTION
Document has been opened, but our ItemGroup node is not found.
Add ItemGroup node to root (multiple ItemGroup nodes are normal).
#>
function AppendItemGroupElementAndChildren([System.Xml.XmlDocument] $doc, [string] $childElemName, [string] $folderName) {
    $nodes = $doc.SelectNodes('//x:Project', $ns);
    if (($null -eq $nodes) -or ($nodes.Count -gt 1)) {
        throw 'Root project node of database project file not found'
    } else {
        $itemGroupElem = AppendItemGroupElement $doc $nodes[0]
        AppendChildElement $doc $itemGroupElem $childElemName $folderName
    }
}

<#
.DESCRIPTION
Validation and doc creation have happened; continue.
Add a child element to an ItemGroup node.
#>
function AddChildToItemGroup([string] $projPath, [System.Xml.XmlDocument] $doc, [string] $childElemName, [string] $folderName) {
    $doc.Load($projPath)
    if ($null -eq $doc.DocumentElement) {
        throw 'Failed to load project file.'
    }
    $nodes = $doc.SelectNodes('//x:ItemGroup', $ns);
    if ($nodes.Count -gt 0) {
        $folderParent = GetElementParent $nodes $childElemName
        if ($null -eq $folderParent) {
            # Didn't find one that already contained a folder child; create new ItemGroup node.
            AppendItemGroupElementAndChildren $doc $childElemName $folderName
        } else {
            AppendChildElement $doc $folderParent $childElemName $folderName
        }
    } else {
        AppendItemGroupElementAndChildren $doc $childElemName $folderName
    }
    $doc.Save($projPath) > $null
}

<#
.DESCRIPTION
Given the path to a .sqlproj file, add a solution folder to it's xml content.
#>
function AddItemGroupChildTo([string] $projPath, [string] $childElementName, [string] $folderName) {
    $doc = New-Object -TypeName 'System.Xml.XmlDocument'
    # @#$%ing namespaces
    $ns = New-Object -TypeName 'System.Xml.XmlNamespaceManager' -ArgumentList @($doc.NameTable)
    $ns.AddNamespace('x', $namespaceURI)
    try {
        AddChildToItemGroup $projPath $doc $childElementName $folderName
    }
    catch {
        Write-Host "Error adding an item to the database project: $_"
    }
}

<#
.DESCRIPTION
Public function; pass full sqlproj path to add the script nodes, yo.
#>
function AddDatabaseProjectItems($projPath) {
    if (ContainsExpectedNamespace $projPath) {
        AddDirectory $projPath 'Scripts\AdHoc'
        AddDirectory $projPath 'Scripts\Migrations'
        AddItemGroupChildTo $projPath 'Folder' 'Scripts\AdHoc'
        AddItemGroupChildTo $projPath 'Folder' 'Scripts\Migrations'
        AddItemGroupChildTo $projPath 'None' 'CommitDatabaseScripts.ps1'
        AddItemGroupChildTo $projPath 'None' 'Common.psm1'
        AddItemGroupChildTo $projPath 'None' 'ExtractResourceScripts.ps1'
        AddItemGroupChildTo $projPath 'None' 'GenerateMigrationScript.ps1'
        AddItemGroupChildTo $projPath 'None' 'UpdateDatabaseStateFile.ps1'
        AddItemGroupChildTo $projPath 'None' 'UpdateProject.scmp'
        AddItemGroupChildTo $projPath 'None' 'DetectChanges.psm1'
    } else {
        throw "Project file doesn't contain expected namespace"
    }
}

<#
Add these nodes to the project file in addition to the actual folders if they don't exist.
<Folder Include="Scripts" />
<Folder Include="Scripts\AdHoc" />
<Folder Include="Scripts\Migrations" />
#>

<#
Add individual items to root:
<None Include="UpdateProject.scmp" />
#>

#AddDatabaseProjectItems "C:\Data\BatchFiles\PSCore\DatabaseMigrationNuget\WorkingSample.proj"