# "source" will actually be the newly generated dacpac
# "target" will actually be the existing state
# see comments in GenerateDiffScript
$global:SourceDacPath = ''
$global:TargetDacPath = ''

$global:DatabaseProjectName = ''
$global:DatabaseProjRootPath = ''
$global:SolutionRootDir = ''
$global:BuildOutputDir = ''

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
}

