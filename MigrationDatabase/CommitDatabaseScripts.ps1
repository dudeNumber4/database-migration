<#
• Looks for scripts in Migrations & AdHoc directory to add to the runtime script folder in the service (see $global:ServiceProjFilePath).
• Scripts in AdHoc will have their project reference deleted after processing if they were added via project right-click.
• Every reference to "$dte" is a dependency on visual studio.  The whole thing could be independent of vs, but it's much easier this way and more convenient to run it.
#>

Import-Module "$PSScriptRoot\Common.psm1" #-Force

# Set after determining solution root
$global:NextScriptNumber = 0
# :Configure: path to service csproj that contains migration runtime files relative to DatabaseMigrationRoot which is the folder named "DatabaseMigration"
$global:ServiceProjFilePath = "$global:DatabaseMigrationRoot\..\DatabaseMigration.csproj"

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
Similar to GetScriptItemGroup, but gets a different ItemGroup parent element; the one that's (sometimes?) necessary in order for the project to not
show a phantom item in the solution explorer.  Also, this element seems to be necessary in order to preclude the file from being part of compilation.
Copy/Pasted (mostly) to CommitJournalScript.psm1 in the nuget scripts.
#>
function GetRemoveItemGroup([System.Xml.XmlDocument] $doc) {
    if ($null -eq $doc) {
        throw 'Expected open project document prior to finding an element.'
    }

    $errMsg = "Unable to find expected initial script in project XML under 'Remove' items."
    $node = $doc.SelectSingleNode('descendant::ItemGroup/None[@Remove="DatabaseMigration\RuntimeScripts\1.sql"]')
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
Returns <ItemGroup> parent that holds references to our script files in the project file.  Very similar to GetRemoveItemGroup.
Copy/Pasted (mostly) to CommitJournalScript.psm1 in the nuget scripts.
#>
function GetScriptItemGroup([System.Xml.XmlDocument] $doc) {
    $doc.Load($global:ServiceProjFilePath) > $null
    if ($null -eq $doc.DocumentElement) {
        throw 'Failed to load project file.'
    }
    $errMsg = 'Unable to find expected initial script'
    #$node = $doc.SelectSingleNode('/Project/ItemGroup/EmbeddedResource[@Include="DatabaseMigration\RuntimeScripts\1.sql"]') works, but more specific
    $node = $doc.SelectSingleNode('descendant::ItemGroup/EmbeddedResource[@Include="DatabaseMigration\RuntimeScripts\1.sql"]')
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
Similar to AppendResourceElement, just adds to different element.  Copy/Pasted to CommitJournalScript.psm1 in the nuget scripts.
Copy/Pasted to CommitJournalScript.psm1 in the nuget scripts.
#>
function AppendRemoveElement([System.Xml.XmlDocument] $doc, [System.Xml.XmlElement] $parent, [string] $scriptFileName) {
    try {
        # None Remove="DatabaseMigration\RuntimeScripts\n.sql"
        $noneElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'None', [System.string]::Empty)
        $removeAttr = $doc.CreateAttribute('Remove')
        $removeAttr.Value = "DatabaseMigration\$global:ScriptFolderName\$scriptFileName"
        $noneElem.Attributes.Append($removeAttr) > $null
        $parent.AppendChild($noneElem) > $null
    }
    catch {
        throw "Error adding script as 'removed' item to project: $_"
    }
}

<#
.DESCRIPTION
We've found our parent ItemGroup in the project file; append our new element referencing our script.  Very similar to AppendRemoveElement.
Copy/Pasted to CommitJournalScript.psm1 in the nuget scripts.
Copy/Pasted (mostly) to CommitJournalScript.psm1 in the nuget scripts.
#>
function AppendResourceElement([System.Xml.XmlDocument] $doc, [System.Xml.XmlElement] $parent, [string] $scriptFileName) {
    try {
        $scriptResourceElem = $doc.CreateNode([System.Xml.XmlNodeType]::Element, 'EmbeddedResource', [System.string]::Empty)
        $includeAttr = $doc.CreateAttribute('Include')
        $includeAttr.Value = "DatabaseMigration\$global:ScriptFolderName\$scriptFileName"
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
Mostly Copy/Pasted to CommitJournalScript.psm1 in the nuget scripts.
#>
function CommitScriptAsResource([string] $initialScriptPath) {
    Write-Host "Adding $initialScriptPath as script #$global:NextScriptNumber" -ForegroundColor DarkGreen
    try {
        $newFilePath = CopyScript $initialScriptPath
        $doc = New-Object -TypeName 'System.Xml.XmlDocument'
        $scriptFileName = [System.IO.Path]::GetFileName($newFilePath)
        $parentElem = GetScriptItemGroup $doc
        AppendResourceElement $doc $parentElem $scriptFileName
        $parentElem = GetRemoveItemGroup $doc
        AppendRemoveElement $doc $parentElem $scriptFileName
        $doc.Save($global:ServiceProjFilePath) > $null
        $global:NextScriptNumber = $global:NextScriptNumber + 1
        $true
    }
    catch {
        Write-Host "Error committing script: $_.  Note that your script may have moved to the RuntimeScripts directory as '$newFilePath' and a reference to it may have been added to your service project."
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
            Start-Sleep -Milliseconds 1250 # GOL, if there are multiples, they stomp on each other in CommitScriptAsResource
            Write-Host "Removing Ad-Hoc file $_ from database project." -ForegroundColor DarkGreen
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
$global:ServiceProjFilePath = "$global:SolutionRootDir$global:ServiceProjFilePath"
EnsureExpectedDirectoriesExist

if (TestScriptRelatedPaths) { # else error written to console
    $global:NextScriptNumber = GetNextScriptNumber
    ProcessMigrationDirectory
    ProcessAdHocDirectory
}