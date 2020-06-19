<#
• Looks for scripts in Migrations & AdHoc directory to add to script folder in the service and as an embedded resource to the service project (see $global:ServiceProjFilePath).
• Scripts in AdHoc will have their project reference deleted after processing if they were added via project right-click.
• Every reference to "$dte" is a dependency on visual studio.  The whole thing could be independent of vs, but it's much easier this way and more convenient to run it.
#>

Import-Module "$PSScriptRoot\Common.psm1" -Force

# Set after determining solution root
$global:NextScriptNumber = 0
$global:ServiceProjFilePath = 'C:\source\database-migration\DatabaseMigration\DatabaseMigration.csproj'

<#
.DESCRIPTION
Script files are numbered (1.sql should be the migration table creation/update script and is assumed to always be present).  This gets the next number to use based on the scripts we already have.
#>
function GetNextScriptNumber {
    Write-Host "Counting scripts in $global:ResourceFolderPath" -ForegroundColor DarkGreen
    $max = (Get-ChildItem -Path $global:ResourceFolderPath -File | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_) } | Measure-Object -Max).Maximum
    $max + 1
}

function TestScriptRelatedPaths {
    # dunno how to chain these
    Write-Host "Testing script related paths." -ForegroundColor DarkGreen
    if (Test-Path $global:MigrationScriptPath) {
        if (Test-Path $global:AdHocScriptPath) {
            if (Test-Path $global:ResourceFolderPath) {
                $true
            }
            else {
                throw "Expected to find folder: $global:ResourceFolderPath"
            }
        }
        else {
            throw "AdHoc script path invalid: $global:MigrationScriptPath"
        }
    }
    else {
        throw "Migration script path invalid: $global:AdHocScriptPath"
    }
}

<#
.DESCRIPTION
Returns <ItemGroup> parent that holds references to our script files in the project file.
#>
function GetScriptItemGroup([System.Xml.XmlDocument] $doc) {
    $doc.Load($global:ServiceProjFilePath) > $null
    if ($null -eq $doc.DocumentElement) {
        throw 'Failed to load project file.'
    }
    $errMsg = 'Unable to find expected initial script'
    #$node = $doc.SelectSingleNode('/Project/ItemGroup/EmbeddedResource[@Include="RuntimeScripts\1.sql"]') works, but more specific
    $node = $doc.SelectSingleNode('descendant::ItemGroup/EmbeddedResource[@Include="RuntimeScripts\1.sql"]')
    if ($null -eq $node) {
        throw $errMsg
    } else {
        $result = $node.ParentNode
        if ($null -eq $result) {
            throw $errMsg
        }
        elseif ($result -is [Array]) {
            $result[0]
        } else {
            $result
        }
    }
}

<#
.DESCRIPTION
Copies script from where it was created to it's final resting place and returns the new script file path.
#>
function CopyScript([string] $scriptPath) {
    $finalRestingPlace = [System.IO.Path]::Combine($global:ResourceFolderPath, "$global:NextScriptNumber.sql")
    Copy-Item $scriptPath $finalRestingPlace > $null
    $finalRestingPlace
}

<#
.DESCRIPTION
We've found our parent ItemGroup in the project file; append our new element referencing our script.
#>
function AppendResourceElement([System.Xml.XmlDocument] $doc, [System.Xml.XmlElement] $parent, [string] $scriptFileName) {
    try {
        $scriptResourceElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'EmbeddedResource', [System.string]::Empty)
        $includeAttr = $doc.CreateAttribute('Include')
        $includeAttr.Value = "$global:ScriptFolderName\$scriptFileName"
        $scriptResourceElem.Attributes.Append($includeAttr) > $null
        
        $copyElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'CopyToOutputDirectory', [System.string]::Empty)
        $copyElem.InnerText = 'PreserveNewest'
        $scriptResourceElem.AppendChild($CopyElem) > $null
        $parent.AppendChild($scriptResourceElem) > $null
    }
    catch {
        throw "Error adding script as resource to project: $_"
    }
}

<#
.DESCRIPTION
A script has been created and identified to be committed as a resource.  Move it to it's final resting place and add it as a resource to the service project.
#>
function CommitScriptAsResource([string] $initialScriptPath) {
    Write-Host "Adding $initialScriptPath as script #$global:NextScriptNumber" -ForegroundColor DarkGreen
    try {
        $newFilePath = CopyScript $initialScriptPath
        $doc = New-Object -TypeName 'System.Xml.XmlDocument'
        $parentElem = GetScriptItemGroup $doc
        $scriptFileName = [System.IO.Path]::GetFileName($newFilePath)
        AppendResourceElement $doc $parentElem $scriptFileName
        $doc.Save($global:ServiceProjFilePath) > $null
        $true
    }
    catch {
        Write-Host "Error committing script: $_.  Note that your script may have moved to the RuntimeScripts directory as '$newFileName'."
        $false
    }
    finally {
        $doc = $null
    }
}

<#
.DESCRIPTION
Process $global:MigrationScriptPath.
Expected; 0 (may be running this script just for AdHoc) or 1 file.  If multiples, we assume something went wrong with previous run; probably should've deleted?
#>
function ProcessMigrationDirectory {
    Write-Host "Processing scripts in $global:MigrationScriptPath" -ForegroundColor DarkGreen
    try {
        $scriptCount = (Get-Childitem $global:MigrationScriptPath | Measure-Object).Count
        if ($scriptCount -gt 1) {
            throw "Expected 0 or 1 file.  Was a previous state migration file not processed correctly, or did you mean to delete a previously generated script?"
            exit
        }
        else {
            if ($scriptCount -eq 1) {
                $scriptPath = (Get-Childitem -Path $global:MigrationScriptPath).FullName | Select-Object -First 1
                $result = CommitScriptAsResource $scriptPath
                if ($result -eq $false) {
                    Write-Host 'Error processing migration directory; exiting.'
                    exit
                }
                Remove-Item $scriptPath
            }
        }
    } 
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}

<#
.DESCRIPTION
Given $databaseProjectItem (a reference to the database project), drill down into known folders and find the script that may exist there.
#>
function FindScriptInProjectItems($projectItem, $scriptName) {
    $result = $projectItem.ProjectItems | Select-Object -Expand ProjectItems | Where-Object { $_.Name -eq $scriptName }
    if ($null -eq $result) {
        $projectItem.ProjectItems | ForEach-Object { FindScriptInProjectItems $_ $scriptName }
    }
    $result
}

<#
.DESCRIPTION
Process $global:AdHocScriptPath
Add scripts found there to known folder.
#>
function ProcessAdHocDirectory {
    Write-Host "Processing scripts in $global:AdHocScriptPath" -ForegroundColor DarkGreen
    try {
        Get-Childitem -Path $global:AdHocScriptPath | ForEach-Object {
            $result = CommitScriptAsResource $_.FullName
            if ($result -eq $false) {
                Write-Host 'Error processing AdHoc directory; exiting.'
                exit
            }
            # delete the file
            Remove-Item $_.FullName
            # Remove the item from the project if present.  Active project has been enforced to be the database project.
            $scriptProjectItem = FindScriptInProjectItems $dte.ActiveSolutionProjects $_.Name # file name only
            if ($null -ne $scriptProjectItem) {
                # Remove the project item; we added it as a resource, we don't want it as part of DB project anymore (it will normally be there because we right-clicked and added from the Ad-Hoc dir).
                $scriptProjectItem.Remove()
                # Issue save command to remove the above file reference from the database project file.
                $dte.ExecuteCommand("File.SaveAll")
            }
            $global:NextScriptNumber = $global:NextScriptNumber + 1
        }
    } 
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}

# MAIN
EnsureDatabaseProjectSelected
SetProjectBasedGlobals
EnsureExpectedDirectoriesExist

if (TestScriptRelatedPaths) { # else error written to console
    $global:NextScriptNumber = GetNextScriptNumber
    ProcessMigrationDirectory
    ProcessAdHocDirectory
}