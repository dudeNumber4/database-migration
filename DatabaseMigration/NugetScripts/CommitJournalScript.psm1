# These functions are (mostly) copy/pasted from CommitDatabaseScripts.ps1 back in the database project.
# I tried to use those directly, but they require the database project to be selected, must run in package manager explorer, and, most importantly,
# just randomly/erroneously started failing to compile (run time compile) when run from another location.

$scriptFileName = '1.sql'
$runtimeScriptsDirRelativePath = 'DatabaseMigration\RuntimeScripts'

<#
.DESCRIPTION
Returns <ItemGroup> parent that holds references to our script files in the project file.  Very similar to GetRemoveItemGroup.
#>
function GetScriptItemGroup([System.Xml.XmlDocument] $doc, [string] $serviceProjFilePath) {
    $doc.Load($serviceProjFilePath) > $null
    if ($null -eq $doc.DocumentElement) {
        throw 'Failed to load project file.'
    }
    $node = $doc.SelectSingleNode("descendant::ItemGroup/EmbeddedResource[@Include='$runtimeScriptsDirRelativePath\$scriptFileName']")
    if ($null -eq $node) {
        $node = $doc.SelectSingleNode('descendant::EmbeddedResource/CopyToOutputDirectory')
        if ($null -eq $node) {
            # create a new parent ItemGroup, no suitable element exists.
            $node = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'ItemGroup', [System.string]::Empty)
            $doc.DocumentElement.AppendChild($node)
        } else {
            # In this case, we have an existing embedded resource node, add to it.  Guaranteed to have 2 parents by selector above.
            if ($node -is [Array]) {
                $node[0].ParentNode.ParentNode
            } else {
                $node.ParentNode.ParentNode
            }
        }
    } else {
        throw "Found journal creation script referenced in project file $serviceProjFilePath.  Expected it NOT to be there."
    }
}

<#
.DESCRIPTION
Similar to GetScriptItemGroup, but gets a different ItemGroup parent element; the one that's (sometimes?) necessary in order for the project to not
show a phantom item in the solution explorer.  Also, this element seems to be necessary in order to preclude the file from being part of compilation.
#>
function GetRemoveItemGroup([System.Xml.XmlDocument] $doc) {
    if ($null -eq $doc) {
        throw 'Expected open project document prior to finding an element.'
    }
    $node = $doc.SelectSingleNode("descendant::ItemGroup/None[@Remove='$runtimeScriptsDirRelativePath\$scriptFileName']")
    if ($null -eq $node) {
        $node = $doc.SelectSingleNode('descendant::ItemGroup/None')
        if ($null -eq $node) {
            # create a new parent ItemGroup, no suitable element exists.
            $node = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'ItemGroup', [System.string]::Empty)
            $doc.DocumentElement.AppendChild($node)
        } else {
            $node.ParentNode
        }
    } else {
        $node.ParentNode
    }
}

<#
.DESCRIPTION
Similar to AppendResourceElement, just adds to different element.
#>
function AppendRemoveElement([System.Xml.XmlDocument] $doc, [System.Xml.XmlElement] $parent) {
    try {
        # None Remove="DatabaseMigration\RuntimeScripts\n.sql"
        $noneElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'None', [System.string]::Empty)
        $removeAttr = $doc.CreateAttribute('Remove')
        $removeAttr.Value = "$runtimeScriptsDirRelativePath\$scriptFileName"
        $noneElem.Attributes.Append($removeAttr) > $null
        $parent.AppendChild($noneElem) > $null
    }
    catch {
        throw "Error adding journal creation script as 'removed' item to project: $_"
    }
}

<#
.DESCRIPTION
We've found our parent ItemGroup in the project file; append our new element referencing our script.  Very similar to AppendRemoveElement.
#>
function AppendResourceElement([System.Xml.XmlDocument] $doc, [System.Xml.XmlElement] $parent) {
    try {
        $scriptResourceElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'EmbeddedResource', [System.string]::Empty)
        $includeAttr = $doc.CreateAttribute('Include')
        $includeAttr.Value = "$runtimeScriptsDirRelativePath\$scriptFileName"
        $scriptResourceElem.Attributes.Append($includeAttr) > $null
        
        $copyElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'CopyToOutputDirectory', [System.string]::Empty)
        $copyElem.InnerText = 'PreserveNewest'
        $scriptResourceElem.AppendChild($CopyElem) > $null
        $parent.AppendChild($scriptResourceElem) > $null
    }
    catch {
        throw "Error adding journal creation script as resource to project: $_"
    }
}

<#
.DESCRIPTION
Commit initial script as a resource to the service project.
#>
function CommitScriptAsResource([string] $journalScriptPath, [string] $runtimeScriptsDir, [string] $serviceProjectFilePath) {
    Write-Host 'Adding initial database script to script runtime directory.' -ForegroundColor Green
    try {
        $finalRestingPlace = [System.IO.Path]::Combine($runtimeScriptsDir, $scriptFileName)
        Copy-Item $journalScriptPath $finalRestingPlace > $null
        $doc = New-Object -TypeName 'System.Xml.XmlDocument'
        $parentElem = GetScriptItemGroup $doc $serviceProjectFilePath
        AppendResourceElement $doc $parentElem
        $parentElem = GetRemoveItemGroup $doc
        AppendRemoveElement $doc $parentElem
        $doc.Save($serviceProjectFilePath) > $null
        $true
    }
    catch {
        Write-Host "Error committing initial script ($scriptFileName): $_" -ForegroundColor Red
        $false
    }
    finally {
        $doc = $null
    }
}
