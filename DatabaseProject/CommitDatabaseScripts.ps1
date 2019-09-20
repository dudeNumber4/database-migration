﻿<#
	• Looks for scripts in Migrations & AdHoc directory to add to the resource file in the console app.  Also updates the known file DatabaseState.dacpac to the current state.
    Migrations will be added to resource and added to the database journal table; assumes developer has already made these changes.
    AdHoc will be added to resource and NOT added to the database journal table; assumes developer has written the script but wants it to executed upon next startup of console.
    Scripts in AdHoc will have their project reference deleted after processing if they were added via project right-click.
	• Check :Configure: for things to change when plugging into another solution.
	• Every reference to "$dte" is a dependency on visual studio.  The whole thing could be independent of vs, but it's much easier this way and more convenient to run it.
#>

Import-Module "$PSScriptRoot\Common.psm1" #-Force

$global:MigrationTableName = 'MigrationsJournal'
$global:MigrationTableScriptNameColumn = 'ScriptName'
$global:MigrationTableAppliedAttemptedColumn = 'AppliedAttempted'
$global:MigrationTableAppliedCompletedColumn = 'AppliedCompleted'
# :Configure: Adjust as necessary.  Assumes all devs can share same local connection string.
$global:conStr = "Server=.\SQLEXPRESS;Database=$DatabaseName;Trusted_Connection=Yes"
$global:ResourceFilePath = '' # Set after determining solution root
$global:MigrationScriptPath = ''
$global:AdHocScriptPath = ''
# :Configure: Your service project name in place of "Migrator."  This file begins as empty resource file generated by `new ResourceWriter()`
#             Use Empty.resources as a reset/starting point.
$global:ResourceFileRelativePath = 'Migrator\DatabaseMigration\DatabaseMigrationScripts.resources'

# Caller must close the connection
function get-open-connection() {
    try {
        $result = New-Object System.Data.SqlClient.SqlConnection
        $result.ConnectionString = $conStr
        $result.Open()
        $result
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}

# Assumes open connection
function get-command([System.Data.SqlClient.SqlConnection] $con, [string] $cmdText) {
    $result = New-Object System.Data.SqlClient.SqlCommand
    $result.CommandText = $cmdText
    $result.Connection = $con
    $result
}

<#
.DESCRIPTION
Adds a row to the script/log table for the current developer
Pre: Assumes developer has already made the database changes for his/her database instance.
      GenerateDiffScript has run and left a script in the migration folder, or someone has added script(s) to the AdHoc folder.
#>
function AddTableEntry([string] $scriptPath) {
    try {
        Write-Host "Adding record to database migration table for $scriptPath" -ForegroundColor Blue
        $fileName = [System.IO.Path]::GetFileName($scriptPath) # We just write the file name to the Database.
        $con = get-open-connection
        $cmd = get-command $con "insert $global:MigrationTableName($global:MigrationTableScriptNameColumn, $global:MigrationTableAppliedAttemptedColumn, $global:MigrationTableAppliedCompletedColumn) values ('$fileName', GetUtcDate(), 1)"
        $cmd.ExecuteNonQuery() > $null
        $con.Close() > $null
    }
    catch {
        Write-Host "Error (below) adding entry to table MigrationsJournal.  System.Data.SqlClient not present?" -ForegroundColor Red
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
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
    if (Test-Path $global:MigrationScriptPath) {
        if (Test-Path $global:AdHocScriptPath) {
            if (Test-Path $global:ResourceFilePath) {
                $true
            }
            else {
                throw "Expected to find resource file: $global:ResourceFilePath"
            }
        }
        else {
            throw "Migration script path invalid: $global:MigrationScriptPath"
        }
    }
    else {
        throw "AdHoc script path invalid: $global:AdHocScriptPath"
    }
}

# Pre: EnsureDatabaseProjectSelected & SetProjectBasedGlobals have been called.
function set-script-source-paths {
    $global:MigrationScriptPath = "$global:DatabaseProjRootPath\Scripts\Migrations"
    $global:AdHocScriptPath = "$global:DatabaseProjRootPath\Scripts\AdHoc"
    $global:ResourceFilePath = "$global:SolutionRootDir\$global:ResourceFileRelativePath"
}

<#
.DESCRIPTION
Prevent overwriting an existing key (unfortunately it won't blow up, it'll just silently overwrite).
#>
function ResourceContains([string] $key) {
    $r = New-Object System.Resources.ResourceReader -ArgumentList $global:ResourceFilePath
    try {
        # returns true if found
        $null -ne ($r | Where-Object -Property Key -EQ -Value $key)
    }
    finally {
        $r.Close() > $null
    }
}

<#
.DESCRIPTION
Adds script at path passed in to the known resource file @ $global:ResourceFilePath
#>
function AddToResource([string] $scriptPath, [bool]$adHoc = $False) {
    Write-Host "Adding $scriptPath to resource $global:ResourceFilePath" -ForegroundColor Blue

    try {
        $fileName = [System.IO.Path]::GetFileName($scriptPath) # File name is resource key.
        if (ResourceContains $fileName) {
            throw "Resource file already contains $fileName!"
        }
        else {
            $scriptContent = Get-Content -Path $scriptPath -Delimiter '\0'
            if ($adHoc) {
                # For ad-hoc scripts add a using statement to set the database so we don't have to require fully qualified database object names.
                $scriptContent = "use [$global:DatabaseName];$([System.Environment]::NewLine)$scriptContent"
            }
            $writer = New-Object System.Resources.ResourceWriter -ArgumentList $global:ResourceFilePath
            try {
                $writer.AddResource($fileName, $scriptContent)
            }
            finally {
                $writer.Close() > $null
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
                AddTableEntry $scriptPath
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
function FindScriptInProjectItems($databaseProjectItem, $scriptName) {
    $result = $databaseProjectItem | Select-Object -Expand ProjectItems | Where-Object { $_.Name -eq 'Scripts' -or $_.Name -eq 'AdHoc' -or $_.Name -eq $scriptName }
    if ($result.Name -eq $scriptName) {
        $result
    }
    if ($null -ne $result) {
        FindScriptInProjectItems $result $scriptName
    }
    # else we didn't find it.
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
            AddToResource $_.FullName $True
            Remove-Item $_.FullName # delete the file
            $databaseProjectObject = $dte.Solution.Projects | Where-Object { $_.Name -eq $global:DatabaseProjectName }
            $scriptProjectItem = FindScriptInProjectItems $databaseProjectObject $_.Name # file name only
            if ($null -ne $scriptProjectItem) {
                $scriptProjectItem.Remove() # Remove the project item so it's not an orphan
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
set-script-source-paths

if (TestScriptRelatedPaths) {
    # else error written to console
    ProcessMigrationDirectory
    ProcessAdHocDirectory
}