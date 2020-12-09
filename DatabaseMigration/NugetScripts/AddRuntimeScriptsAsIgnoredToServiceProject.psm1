<#
.DESCRIPTION
Adds parent RuntimeScripts folder to project as an ignored folder (individual scripts will be resources.)
#>
function AddRuntimeScriptsProjectReference($serviceProjectFilePath)
{
    Write-Host "Adding scripts project reference to $serviceProjectFilePath" -ForegroundColor Green
    $doc = New-Object -TypeName 'System.Xml.XmlDocument'
    $doc.Load($serviceProjectFilePath) > $null
    $parent = $doc.SelectSingleNode('/Project')
    if ($null -eq $parent) {
        throw 'Unable to find root project node of service.'
    } else {
        $remove = "DatabaseMigration\RuntimeScripts\**"
        # <ItemGroup>
        #   <Compile Remove=
        #   <EmbeddedResource Remove=
        #   <None Remove=

        # See if elements exist
        $existingItemGroupElem
        $existingCompileElem = $doc.SelectSingleNode("descendant::ItemGroup/Compile[@Remove='$remove']")
        if ($null -ne $existingCompileElem) {
            $existingItemGroupElem = $existingCompileElem.ParentNode
        }
        $existingResourceElem = $doc.SelectSingleNode("descendant::ItemGroup/EmbeddedResource[@Remove='$remove']")
        if ($null -ne $existingResourceElem) {
            $existingItemGroupElem = $existingResourceElem.ParentNode
        }
        $existingNoneElem = $doc.SelectSingleNode("descendant::ItemGroup/None[@Remove='$remove']")
        if ($null -ne $existingNoneElem) {
            $existingItemGroupElem = $existingNoneElem.ParentNode
        }

        if ($null -eq $existingItemGroupElem) {
            $itemGroupElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'ItemGroup', [System.string]::Empty)
            AddCompileElem $doc $itemGroupElem
            AddResourceElem $doc $itemGroupElem
            AddNoneElem $doc $itemGroupElem
            #GOL: this node must come before other nodes that reference these items.  If not, the whole parent folder won't appear in the project structure.
            $parent.PrependChild($itemGroupElem) > $null
        } else {
            if ($null -eq $existingCompileElem) {
                AddCompileElem $doc $existingItemGroupElem
            }
            if ($null -eq $existingResourceElem) {
                AddResourceElem $doc $existingItemGroupElem
            }
            if ($null -eq $existingNoneElem) {
                AddNoneElem $doc $existingItemGroupElem
            }
        }
        
        $doc.Save($serviceProjectFilePath) > $null
    }
}

function AddCompileElem($doc, $itemGroupElem) {
    $compileElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'Compile', [System.string]::Empty)
    $removeAttr = $doc.CreateAttribute('Remove')
    $removeAttr.Value = $remove
    $compileElem.Attributes.Append($removeAttr) > $null
    $itemGroupElem.AppendChild($compileElem) > $null
}

function AddResourceElem($doc, $itemGroupElem) {
    $resourceElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'EmbeddedResource', [System.string]::Empty)
    $removeAttr = $doc.CreateAttribute('Remove')
    $removeAttr.Value = $remove
    $resourceElem.Attributes.Append($removeAttr) > $null
    $itemGroupElem.AppendChild($resourceElem) > $null
}

function AddNoneElem($doc, $itemGroupElem) {
    $noneElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'None', [System.string]::Empty)
    $removeAttr = $doc.CreateAttribute('Remove')
    $removeAttr.Value = $remove
    $noneElem.Attributes.Append($removeAttr) > $null
    $itemGroupElem.AppendChild($noneElem) > $null
}
