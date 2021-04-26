# "source" will actually be the newly generated dacpac
# "target" will actually be the existing state
# see comments in GenerateDiffScript
$global:SourceDacPath = ''
$global:TargetDacPath = ''

# :Configure: Match this with your database project/database name
$global:DatabaseProjectName = ''
$global:DatabaseProjRootPath = ''
$global:SolutionRootDir = ''
$global:BuildOutputDir = ''
$global:MigrationScriptPath = ''
$global:AdHocScriptPath = ''
$global:ScriptFolderName = 'RuntimeScripts'
# :Configure: set/confirm your path to the DatabaseMigration dir (under service project) from solution root (leave leading forward slash).
#   The configuration script delivered by the nuget package should've created this directory if it din't already exist.
#   We have a nested folder by the same name here, but when added to another project, the first portion won't be "DatabaseMigration""
$global:DatabaseMigrationRoot = '/DatabaseMigration/DatabaseMigration'
$global:ScriptFolderPath = "$global:DatabaseMigrationRoot\$global:ScriptFolderName"
$global:ResourceFolderPath = ''
$global:SQLPackagePath = ''
# :Configure: Adjust as necessary.  Assumes all devs can share same local connection string.
$global:conStr = "Server=.\SQLEXPRESS;Database=$global:DatabaseProjectName;Trusted_Connection=Yes"

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
    $global:TargetDacPath = "$global:DatabaseProjRootPath\databaseState.dacpac"
    $global:SourceDacPath = "$global:BuildOutputDir\$global:DatabaseProjectName.dacpac" # see comments in GenerateDiffScript
    $global:MigrationScriptPath = "$global:DatabaseProjRootPath\Scripts\Migrations"
    $global:AdHocScriptPath = "$global:DatabaseProjRootPath\Scripts\AdHoc"
    $global:ResourceFolderPath = "$global:SolutionRootDir\$global:ScriptFolderPath"
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
#>
function UpdateDatabaseStateDacPac {
    try {
        Write-Host "Updating database state file [$global:SourceDacPath] -> [$global:TargetDacPath]." -ForegroundColor DarkGreen
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
To be called by developer who has updated the database project and wants to build a dacpac in prep for creating a diff script, or any time we want the dacpac state to be updated.
Pre: UpdateProject.scmp has been used to update the database project.  Previous database state lives in ./DatabaseState.dacpac
#>
function BuildDacpac {
    Write-Host 'Building database project' -ForegroundColor DarkGreen
    try {
        # $dte.ExecuteCommand('Build.BuildSelection') won't work reliably; there is NO WAY to set the current project.
        # Update: now enforcing the user select the database project
        #Write-Host "Building Database Project [$global:DatabaseProjectName] to [$global:BuildOutputDir] using [$global:MSBuildPath]" -ForegroundColor DarkGreen
        #& $global:MSBuildPath /p:OutDir=$global:BuildOutputDir $ProjPath
  
        # target path should've been set to what was the previous state of the database.
        if (-not (Test-Path $global:TargetDacPath)) { # "source": see GenerateDiffScript
            throw "Expected file [$global:TargetDacPath], to be present, but it's not. That file should've been generated upon branch creation. Have you run deploy-database-git-scripts.ps1? See ReadMe."
        }

        #$dte.ExecuteCommand('Build.BuildOnlyProject') # nope
        # This is supposed to just build the selected project, but it seems to build all.  Sometimes?
        $dte.ExecuteCommand('Build.BuildSelection')
        # The above command is asynchronous.  The subsequent functions rely on the build having finished.  Sleep is easiest; small price to pay.
        Start-Sleep -Seconds 6

        if (-not (Test-Path $global:SourceDacPath)) { # "source": see GenerateDiffScript
            throw "Expected build to generate file [$global:SourceDacPath], but it did not. That file is necessary in order to generate a diff script."
        }
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
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
Finds a file located within the current VS running location.
$DevEnvExe comes from ($dte).FileName, path to IDE exe
#>
function FindMSPath([string] $DevEnvExe, [string] $TargetExeName) {
    Write-Host "Searching for $TargetExeName..." -ForegroundColor DarkGreen
    $InitialHostLocation = Get-Location
    
    try {
        $parentDir = [System.IO.Path]::GetDirectoryName($DevEnvExe)
        Set-Location $parentDir
        # We have to exclude the forking amd version of msbuild. -Exclude doesn't work.  -notcontains doesn't work.
        # Update: this was present when searching for msbuild.  Not doing that anymore, but it won't hurt anything.
        $result = Get-ChildItem -Include $TargetExeName -Recurse | Where-Object { $_.FullName -notlike '*amd64*' }
        while ($null -eq $result) {
            # null must come first
            $parentDir = [System.IO.Directory]::GetParent($parentDir)
            if (Test-Path $parentDir) {
                # Ensure no endless loop
                Set-Location $parentDir
                $result = Get-ChildItem -Include $TargetExeName -Recurse | Where-Object { $_.FullName -notlike '*amd64*' }
            }
            else {
                break
            }
        }
    }
    finally {
        Set-Location $InitialHostLocation > $null # reset location
    }

    if ($result -is [Array]) {
        # If we find multiples, take the last one found (should be most current, e.g. multiple copies of msbuild)
        $result = $result[$result.Length - 1]
    }

    # Ensure it's a valid path
    if (Test-Path $result) {
        $result.FullName
    }
    else {
        ''
    }
}

<#
.DESCRIPTION
Search for dependent executable(s)
#>
function FindExecutables() {
    # This one seems to have to search several dirs above the next one and takes quite awhile.
    # Update: now building directly from automation.
    #$global:MSBuildPath = FindMSPath (($dte).FileName) 'msbuild.exe'
    $global:SQLPackagePath = FindMSPath (($dte).FileName) 'sqlpackage.exe'
}

function TestExecutablePaths {
    if (Test-Path $global:SQLPackagePath) {
        $true
    }
    else {
        throw 'Can''t resolve sqlpackage.exe path.  Is data tools installed?'
    }
}

<#
.DESCRIPTION
Easiest way to verify that the build output will be where expected.
#>
function EnsureDebugConfigurationSelected {
    if ($dte.ActiveSolutionProjects.Object.CurrentConfigName.ConfigName -ne 'Debug') {
        throw 'Please select Debug configuration and run again.'
    }
}

# Caller must close the connection
function GetOpenConnection {
    try {
        $result = New-Object System.Data.SqlClient.SqlConnection
        $result.ConnectionString = $global:conStr
        $result.Open()
        $result
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}
