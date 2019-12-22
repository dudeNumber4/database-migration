<#
• Looks for scripts in Migrations & AdHoc directory to add to the resource file in the console app.  Also updates the known file DatabaseState.dacpac to the current state.
Migrations will be added to resource and added to the database journal table; assumes developer has already made these changes.
AdHoc will be added to resource and NOT added to the database journal table; assumes developer has written the script but wants it to executed upon next startup of console.
Scripts in AdHoc will have their project reference deleted after processing if they were added via project right-click.
• Every reference to "$dte" is a dependency on visual studio.  The whole thing could be independent of vs, but it's much easier this way and more convenient to run it.
#>

Import-Module "$PSScriptRoot\Common.psm1" #-Force

$global:MigrationTableName = 'MigrationsJournal'
$global:MigrationTableScriptNameColumn = 'ScriptName'
$global:MigrationTableAppliedAttemptedColumn = 'AppliedAttempted'
$global:MigrationTableAppliedCompletedColumn = 'AppliedCompleted'
$global:ScriptAppliedColumn = 'ScriptApplied'
$global:MsgColumn = 'Msg'
# Set after determining solution root
$global:ResourceFileBackupPath = ''
$global:JournalTableCreationScriptPath = ''
$global:NewResources = @()
$global:NextScriptKey = 0

# Caller must clean up
function GetResourceWriter {
    New-Object System.Resources.ResourceWriter -ArgumentList $global:ResourceFilePath
}

<#
.DESCRIPTION
Script resource keys are ordered except our pre-required create journal script.  This gets the next key (int) to use based on the resources we already have.
LoadExistingResources must have been called first.
#>
function GetNextScriptKey {
    Write-Host "Counting scripts in $global:ResourceFilePath" -ForegroundColor Blue
    $r = GetResourceReader $global:ResourceFileBackupPath
    try {
        $junkref = 0
        # you can't split pipes.  Much sadness.
        # Find the max of all keys where the key converts to int
        $max = ($r | Where-Object { [int]::TryParse($_.Key, [ref] $junkref) } | Select-Object -ExpandProperty Key | ForEach-Object { [System.Convert]::ToInt32($_) } | Measure-Object -Max).Maximum
        # Leave it at this number because the call to add a new script will increment it.
        if ($null -eq $max) {
            $max = 0
        }
        Write-Host "Counted $max existing scripts." -ForegroundColor Blue
        $max
    }
    finally {
        $r.Close() > $null
    }
}

<#
.DESCRIPTION
Takes the latest build from BuildDacPac and overwrites ./DatabaseState.dacpac with that.
Pre: GenerateDiffScript has run.
#>
function UpdateDatabaseStateDacPac {
    try {
        Write-Host "Updating database state file [$global:SourceDacPath] -> [$global:TargetDacPath]." -ForegroundColor Blue
        [System.IO.File]::Delete($global:TargetDacPath) > $null
        # Copy from output dir to project location.
        [System.IO.File]::Copy($global:SourceDacPath, $global:TargetDacPath) > $null
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}

function TestScriptRelatedPaths {
    # dunno how to chain these
    Write-Host "Testing script related paths." -ForegroundColor Blue
    if (Test-Path $global:MigrationScriptPath) {
        if (Test-Path $global:AdHocScriptPath) {
            if (Test-Path $global:ResourceFilePath) {
                if (Test-Path $global:JournalTableCreationScriptPath) {
                    $true
                }
                else {
                    throw "Expected to find journal table creation script: $global:JournalTableCreationScriptPath"
                }
            }
            else {
                throw "Expected to find resource file: $global:ResourceFilePath"
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

# Pre: EnsureDatabaseProjectSelected & SetProjectBasedGlobals have been called.
function SetScriptSourcePaths {
    $global:ResourceFileBackupPath = "$global:ResourceFilePath.bak"
    $global:JournalTableCreationScriptPath = (Get-ChildItem -Path $global:DatabaseProjRootPath\ -Include "$global:MigrationTableName.sql" -File -Recurse -ErrorAction SilentlyContinue).FullName
}

<#
.DESCRIPTION
Assumes $scriptPath is a file that exists; returns it's content without squashing newlines.
#>
function GetScriptContent([string] $scriptPath) {
    Get-Content -Path $scriptPath -Delimiter '\0'
}

<#
.DESCRIPTION
Adds script at path passed in to the collection of resources $global:NewResources
#>
function AddToResource([string] $scriptPath) {
    $global:NextScriptKey = $global:NextScriptKey + 1
    Write-Host "Adding $scriptPath as script #$global:NextScriptKey" -ForegroundColor Blue
    try {
        $scriptContent = GetScriptContent $scriptPath
        $global:NewResources += @{ Key = ($global:NextScriptKey).ToString(); Value = $scriptContent }
    } 
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}

<#
.DESCRIPTION
The script to create the journal table should be the first script in the resource file.
#>
function EnsureJournalScriptPresent {
    if ($global:NextScriptKey -eq 0) {
        Write-Host "No existing scripts found.  Adding journal table creation script as first." -ForegroundColor Blue
        AddToResource $global:JournalTableCreationScriptPath $True
    }
}

<#
.DESCRIPTION
Write out new resources we've loaded to $global:ResourceFilePath
#>
function FlushResourcesToResourceFile() {
    $writer = GetResourceWriter
    try {
        Write-Host "Writing existing scripts to resource file." -ForegroundColor Blue
        CopyExistingResourcesToResourceFile $writer
        Write-Host "Writing new scripts to resource file." -ForegroundColor Blue
        $global:NewResources | ForEach-Object { $writer.AddResource($_.Key, $_.Value) }
    } 
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
    finally {
        $writer.Close() > $null
    }
}

<#
.DESCRIPTION
Write out the resources that existed prior to execution (that we wrote to a .bak file).
This must be called in the context of FlushResourcesToResourceFile because that's where the writer is opened.
#>
function CopyExistingResourcesToResourceFile([System.Resources.ResourceWriter] $writer) {
    $r = GetResourceReader $global:ResourceFileBackupPath
    try {
        $r | ForEach-Object { $writer.AddResource($_.Key, $_.Value) }
    }
    finally {
        $r.Close() > $null
    }
}

<#
.DESCRIPTION
Process $global:MigrationScriptPath.
Expected; 0 (may be running this script just for AdHoc) or 1 file.  If multiples, we assume something went wrong with previous run; probably should've deleted?
#>
function ProcessMigrationDirectory {
    Write-Host "Processing scripts in $global:MigrationScriptPath" -ForegroundColor Blue
    try {
        $scriptCount = (Get-Childitem $global:MigrationScriptPath | Measure-Object).Count
        if ($scriptCount -gt 1) {
            throw "Expected 0 or 1 file.  Was a previous state migration file not processed correctly, or did you mean to delete a previously generated script?"
            exit
        }
        else {
            if ($scriptCount -eq 1) {
                $scriptPath = (Get-Childitem -Path $global:MigrationScriptPath).FullName | Select-Object -First 1
                AddToResource $scriptPath
                UpdateDatabaseStateDacPac
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
Add scripts found there to known resource file.
#>
function ProcessAdHocDirectory {
    Write-Host "Processing scripts in $global:AdHocScriptPath" -ForegroundColor Blue
    try {
        Get-Childitem -Path $global:AdHocScriptPath | ForEach-Object {
            AddToResource $_.FullName
            # delete the file
            Remove-Item $_.FullName
            # Remove the item from the project if present.  Active project has been enforced to be the database project.
            $scriptProjectItem = FindScriptInProjectItems $dte.ActiveSolutionProjects $_.Name # file name only
            if ($null -ne $scriptProjectItem) {
                $scriptProjectItem.Remove() # Remove the project item; we added it to the resource, we don't want it as part of DB project anymore.
            }
        }
        FlushResourcesToResourceFile
    } 
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}

# MAIN
EnsureDatabaseProjectSelected
SetProjectBasedGlobals
SetScriptSourcePaths
EnsureExpectedDirectoriesExist

if (TestScriptRelatedPaths) { # else error written to console
    Write-Host "Creating backup of existing resources to $global:ResourceFileBackupPath" -ForegroundColor Blue
    Copy-Item $global:ResourceFilePath $global:ResourceFileBackupPath # backup existing.  We can't ever add to the file with existing framework objects.
    try {
        # Get the next script nummber based on current scripts
        $global:NextScriptKey = GetNextScriptKey
        EnsureJournalScriptPresent
        ProcessMigrationDirectory
        ProcessAdHocDirectory
    }
    finally {
        Write-Host "Deleting backup resource file." -ForegroundColor Blue
        Remove-Item $global:ResourceFileBackupPath
    }
}