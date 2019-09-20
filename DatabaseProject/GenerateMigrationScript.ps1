<#
	• Builds the database project and generates a diff script between the existing DatabaseState.dacpac and the newly built one.  Puts that script in the Migrations folder and pops it for viewing.
    If approved, developer will run CommitDatabaseScripts to finish the process.
	• Check :Configure: for things to change when plugging into another solution.
	• Every reference to "$dte" is a dependency on visual studio.  The whole thing could be independent of vs, but it's much easier this way and more convenient to run it.
	• Check ReadMe for test plan.
#>

Import-Module "$PSScriptRoot\Common.psm1" #-Force

#$global:MSBuildPath = ''
$global:SQLPackagePath = ''
$global:InitialHostLocation = Get-Location # We will have to reset to our initial location
$global:ScriptOutputPath = ''

<#
.DESCRIPTION
Finds a file located within the current VS running location.
$DevEnvExe comes from ($dte).FileName, path to IDE exe
#>
function FindMSPath([string] $DevEnvExe, [string] $TargetExeName) {
    Write-Host "Searching for $TargetExeName..." -ForegroundColor Blue
    $parentDir = [System.IO.Path]::GetDirectoryName($DevEnvExe)
    Set-Location $parentDir
    #  We have to exclude the forking amd version of msbuild. -Exclude doesn't work.  -notcontains does not work.
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

    Set-Location $InitialHostLocation > $null # Set back to solution location.
}

<#
.DESCRIPTION
Search for dependent executable(s)
#>
function find-executables() {
    # This one seems to have to search several dirs above the next one and takes quite awhile.
    # Update: now building directly from automation.
    #$global:MSBuildPath = FindMSPath (($dte).FileName) 'msbuild.exe'
    $global:SQLPackagePath = FindMSPath (($dte).FileName) 'sqlpackage.exe'
}

function TestExecutablePaths {
    # dunno how to chain these
    #if (Test-Path $global:MSBuildPath){
    if (Test-Path $global:SQLPackagePath) {
        $true
    }
    else {
        throw 'Can''t resolve sqlpackage.exe path.  Is data tools installed?'
    }
    #} else {
    #  throw 'Can''t resolve MSBuild path: [$MSBuildPath]'
    #}
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
  
        # clean these up; we only want the .dacpac
        #Remove-Item "$global:BuildOutputDir$global:DatabaseProjectName.dll"
        #Remove-Item "$global:BuildOutputDir$global:DatabaseProjectName.pdb"
        # target path has already been set to what was the previous state of the database.

        #$dte.ExecuteCommand('Build.BuildOnlyProject') # nope
        # This is supposed to just build the selected project, but it seems to build all.
        $dte.ExecuteCommand('Build.BuildSelection')
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}

<#
.DESCRIPTION
Uses sqlpackage to generate a diff script between 2 dacpacs.  This diff script will be applied on all other database instances
To bring them to the state defined in ./DatabaseState.dacpac
Pre: BuildDacpac has been called.  $SourceDacPath & $TargetDacPath have been set.
#>
function GenerateDiffScript {
    try {
        Write-Host "Generating diff script between [$global:TargetDacPath] and [$global:SourceDacPath]" -ForegroundColor Blue
        # middle portion of path is assumed constant.
        $global:ScriptOutputPath = "$global:DatabaseProjRootPath\Scripts\Migrations\$([System.DateTime]::UtcNow.ToString('MM-dd-yyyy'))_$([System.DateTime]::UtcNow.Hour)_$([System.DateTime]::UtcNow.Minute).sql"
    
        # source is the new/post state; target is the current/pre state.  Seems backwards.
        & $global:SQLPackagePath /Action:Script /SourceFile:$global:SourceDacPath /TargetFile:$global:TargetDacPath /OutputPath:$global:ScriptOutputPath /TargetDatabaseName:$global:DatabaseName
  
        if ((Test-Path $global:ScriptOutputPath) -ne $true) {
            throw 'Failed to create diff script.'
        }
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }

    PrependCommentTo $global:ScriptOutputPath
}

# Show the script we've generated.
function PopDiffScript([string] $path) {
    $dte.ExecuteCommand('File.OpenFile', $global:ScriptOutputPath)
}

<#
.DESCRIPTION
Pre: GenerateDiffScript has been called to generate the script file.
Load that file, add a comment telling the developer what to do with the new file, write back out.
#>
function PrependCommentTo([string] $path) {
    try {
        Write-Host "Prepending comment to [$path]" -ForegroundColor Blue
        $comment = "/*           DEVELOPER!! README!!$([System.Environment]::NewLine)Review this script (does it drop a table unexpectedly?, etc.)$([System.Environment]::NewLine)If OK, close it and run CommitDatabaseScript.ps$([System.Environment]::NewLine)If the script doesn't look OK, delete this file.$([System.Environment]::NewLine)*/$([System.Environment]::NewLine)$([System.Environment]::NewLine)"
        $existingText = [System.IO.File]::ReadAllText($path)
        [System.IO.File]::Delete($path) > $null
        [System.IO.File]::WriteAllText($path, "$comment$existingText", [System.Text.Encoding]::UTF8) > $null
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script keeps going on error (annoyingly).
    }
}

# MAIN
EnsureDatabaseProjectSelected
SetProjectBasedGlobals
find-executables

if (TestProjectPaths -and TestExecutablePaths) {
    # else error written to console
    BuildDacpac
    GenerateDiffScript
    PopDiffScript
}