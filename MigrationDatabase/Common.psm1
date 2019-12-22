﻿# "source" will actually be the newly generated dacpac
# "target" will actually be the existing state
# see comments in GenerateDiffScript
$global:SourceDacPath = ''
$global:TargetDacPath = ''

$global:DatabaseProjectName = ''
$global:DatabaseProjRootPath = ''
$global:SolutionRootDir = ''
$global:BuildOutputDir = ''
$global:MigrationScriptPath = ''
$global:AdHocScriptPath = ''
# :Configure: Your service project name in place of "Migrator."  This file begins as empty resource file generated by `new ResourceWriter()`
#             Use Empty.resources as a reset/starting point.
$global:ResourceFileRelativePath = 'Migrator\DatabaseMigration\DatabaseMigrationScripts.resources'
$global:ResourceFilePath = ''

function TestProjectPaths {
    # dunno how to chain these
    if (Test-Path $global:BuildOutputDir) {
        if (Test-Path $global:DatabaseProjRootPath) {
            $true
        }
        else {
            throw "Can''t resolve project path: [$ProjPath]"
        }
    }
    else {
        throw "Build output dir doesn''t exist: [$BuildOutputDir]"
    }
}

<#
.DESCRIPTION
I searched long; there just doesn't seem to be a way to programatically select a project (it's not a command, for instance).
#>
function EnsureDatabaseProjectSelected {
    if ($dte.ActiveSolutionProjects.Object.ProjectType -ne 'DatabaseProjectNode') {
        throw 'Please select the database project in the solution explorer and run again.'
    }
}

# Pre: ensure-database-project-selected has been called.
function SetProjectBasedGlobals {
    $global:DatabaseProjectName = $dte.ActiveSolutionProjects.Name
    # The objects in this array are of type PSCustomObject which is a funky COM object from hell.
    # Without ExpandProperty you get another wrapped object of the same type (you can't seem to derefernce value).  Thanks, that took friggin hours.
    $global:DatabaseProjRootPath = $dte.ActiveSolutionProjects.Properties | Where-Object { $_.Name -eq 'LocalPath' } | Select-Object -ExpandProperty Value
    $global:SolutionRootDir = [System.IO.Path]::GetDirectoryName($dte.Solution.FullName)
    # :Configure: Ensure the database project is in it's own directory
    $global:BuildOutputDir = "$global:DatabaseProjRootPath\bin\Debug"
    $global:TargetDacPath = "$global:DatabaseProjRootPath\DatabaseState.dacpac"
    $global:SourceDacPath = "$global:BuildOutputDir\$global:DatabaseProjectName.dacpac" # see comments in GenerateDiffScript
    $global:MigrationScriptPath = "$global:DatabaseProjRootPath\Scripts\Migrations"
    $global:AdHocScriptPath = "$global:DatabaseProjRootPath\Scripts\AdHoc"
    $global:ResourceFilePath = "$global:SolutionRootDir\$global:ResourceFileRelativePath"
}

<#
.DESCRIPTION
These directories must exist.
#>
function EnsureExpectedDirectoriesExist {
    if ((Test-Path $global:MigrationScriptPath) -ne $true) {
        New-Item -ItemType Directory $global:MigrationScriptPath
    }
    if ((Test-Path $global:AdHocScriptPath) -ne $true) {
        New-Item -ItemType Directory $global:AdHocScriptPath
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

<#
.DESCRIPTION
To be called by developer who has updated the database project and wants to build a dacpac in prep for creating a diff script.
Pre: UpdateProject.scmp has been used to update the database project.  Previous database state lives in ./DatabaseState.dacpac
#>
function BuildDacpac {
    Write-Host 'Building database project' -ForegroundColor Blue
    try {
        # $dte.ExecuteCommand('Build.BuildSelection') won't work reliably; there is NO WAY to set the current project.
        # Update: now enforcing the user select the database project
        #Write-Host "Building Database Project [$global:DatabaseProjectName] to [$global:BuildOutputDir] using [$global:MSBuildPath]" -ForegroundColor Blue
        #& $global:MSBuildPath /p:OutDir=$global:BuildOutputDir $ProjPath
  
        # Remove any existing dacpac so we can be assured to have the latest.  If build command fails (flaky), we want the diff script to fail.
        if (Test-Path $global:SourceDacPath) { # "source": see GenerateDiffScript
            Remove-Item $global:SourceDacPath
            Start-Sleep -Milliseconds 50
        }
        # target path has already been set to what was the previous state of the database.

        #$dte.ExecuteCommand('Build.BuildOnlyProject') # nope
        # This is supposed to just build the selected project, but it seems to build all.  Sometimes?
        $dte.ExecuteCommand('Build.BuildSelection')
        # The above command is asynchronous.  The subsequent functions rely on the build having finished.  Sleep is easiest; small price to pay.
        Start-Sleep -Seconds 5
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}

# Caller must clean up
function GetResourceReader([string] $path) {
    New-Object System.Resources.ResourceReader -ArgumentList $path
}
