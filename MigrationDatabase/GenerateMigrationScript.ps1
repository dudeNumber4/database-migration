<#
• Builds the database project and generates a diff script between the existing DatabaseState.dacpac and the newly built one.  Puts that script in the Migrations folder and pops it for viewing.
If approved, developer will run CommitDatabaseScripts to finish the process.
• Every reference to "$dte" is a dependency on visual studio.  The whole thing could be independent of vs, but it's much easier this way and more convenient to run it.
• Check ReadMe for test plan.
#>

Import-Module "$PSScriptRoot\Common.psm1" #-Force

$global:ScriptOutputPath = ''

<#
.DESCRIPTION
Uses sqlpackage to generate a diff script between 2 dacpacs.  This diff script will be applied on all other database instances
To bring them to the state defined in ./DatabaseState.dacpac
Pre: BuildDacpac has been called.  $SourceDacPath & $TargetDacPath have been set.
#>
function GenerateDiffScript {
    try {
        Write-Host "Generating diff script between [$global:TargetDacPath] and [$global:SourceDacPath]" -ForegroundColor DarkGreen
        # middle portion of path is assumed constant.
        $global:ScriptOutputPath = "$global:DatabaseProjRootPath\Scripts\Migrations\$([System.Guid]::NewGuid().Guid).sql"
    
        # source is the new/post state; target is the current/pre state.  Seems backwards.
        & $global:SQLPackagePath /Action:Script /SourceFile:$global:SourceDacPath /TargetFile:$global:TargetDacPath /OutputPath:$global:ScriptOutputPath /TargetDatabaseName:$global:DatabaseProjectName
  
        if ((Test-Path $global:ScriptOutputPath) -ne $true) {
            throw "Failed to create diff script.  Database project didn't build?"
        }
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }

    RemoveSqlCmdSpecificText $global:ScriptOutputPath
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
        Write-Host "Prepending comment to [$path]" -ForegroundColor DarkGreen

        # This sucky ass powershell version or whatever won't allow a normal "here" (multiline) string.
        $comment = '/*        ***   TEST THIS SCRIPT!!!  ***' + $([System.Environment]::NewLine) +
        'Options for testing:' + $([System.Environment]::NewLine) +
        '• If you changed only the database project, remove these comments, save, run CommitDatabaseScript.ps, run the service locally to execute this script, run tests, etc.' + $([System.Environment]::NewLine) +
        '• If you took a backup of your database prior to making changes (very helpful - see ReadMe), you could restore that backup and test this script against it.' + $([System.Environment]::NewLine) +
        '• You could (optionally) take a backup of your local database right now, manually revert the changes and test this script against that.' + $([System.Environment]::NewLine) +
        '• You could restore a copy of the database from another server and test this script against that.' + $([System.Environment]::NewLine) +
        '• You could ask a teammate who hasn''t made the changes to test it.' + $([System.Environment]::NewLine) +
        '• You could commit the changes upon the agreement that a teammate will pull the latest changes, run the service and verify that the script ran (accepting that there is a possibility you may have to undo the recent changes - see ReadMe).' + $([System.Environment]::NewLine) +
        '• Variation of above:' + $([System.Environment]::NewLine) +
        '  • Ensure existing changes are git-committed including database object changes.' + $([System.Environment]::NewLine) +
        '  • Commit this script as a resource file (CommitDatabaseScript.ps).' + $([System.Environment]::NewLine) +
        '  • Drop all tables in your local database.' + $([System.Environment]::NewLine) +
        '  • Run service/tests (all scripts including this new one applied from scratch).' + $([System.Environment]::NewLine) +
        '• If all OK, (optionally remove these comments), save/close this file and run CommitDatabaseScript.ps.  If you are prompted by visual studio telling you that the file encoding has changed (which can happen if you copy/paste into another format); DO NOT SAVE.' + $([System.Environment]::NewLine) +
        '• If not, delete this file. */' + $([System.Environment]::NewLine) + $([System.Environment]::NewLine)

        $existingText = (Get-Content -Path $path -Delimiter '\0')
        (Set-Content -Path $path -Value "$comment$existingText")
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script keeps going on error (annoyingly).
    }
}

<#
.DESCRIPTION
# lines that begin with colon are SqlCmd specific, and the use statement will be followed by a SqlCmd variable which we don't want or need.
# There is a switch for sqlpackage (CommentOutSetVarDeclarations=true) that comments out the main variables, but that's not enough.
#>
function RemoveSqlCmdSpecificText([string] $path) {
    try {
        Write-Host "Removing SqlCmd specific text from [$path]" -ForegroundColor DarkGreen
        # The removal of "SET NOEXEC ON" removes the one line in the chunk like below.  It'll run fine, but still print the message.  It's either this or something much more complex.
        #IF N'$(__IsSqlCmdEnabled)' NOT LIKE N'True'
        #BEGIN
        #    PRINT N'SQLCMD mode must be enabled to successfully execute this script.';
        #    SET NOEXEC ON;
        #END
        (Get-Content -Path $path | Where-Object { $_ -notlike ':*' -and $_ -notlike 'USE *' -and $_ -notlike '*SET NOEXEC ON*' }) | Set-Content -Path $path
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script keeps going on error (annoyingly).
    }
}

<#
.DESCRIPTION
Pre: EnsureDatabaseProjectSelected has been called.
These files get generated when certain changes to the database project are made.  They're part of the regular usage of database projects, but only come into play if you use the full database-project-deployment model.
I can't reproduce currently, but I know I've seen them interfere with how sqlpackage generates the diff files, so we don't want them for that reason.
In any case, it doesn't hurt to nuke them.
#>
function DeleteRefactorLogs {
    Get-ChildItem * -Include *.refactorlog -Recurse | Remove-Item -Force
}

# MAIN
EnsureDatabaseProjectSelected
DeleteRefactorLogs
EnsureDebugConfigurationSelected
SetProjectBasedGlobals
EnsureExpectedDirectoriesExist

if (TestProjectPaths -and TestExecutablePaths) {
    # else error written to console
    BuildDacpac
    GenerateDiffScript
    PopDiffScript
}