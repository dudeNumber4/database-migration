# Add to gitignore database project files
$GitIgnorePath = './.gitignore'
$GitIgnoreContent = @'
# database project files
*.dbmdl
*.jfm
*.refactorlog
*.dacpac

'@
# end gitignore contents

############################################ Create Branch Hook
$CreateBranchHookPath = './.git/hooks/post-checkout'
$CreateBranchHook = @'
#!/bin/bash

# This hook was written by deploy-database-git-scripts.ps1

# checkout is a file checkout – do nothing
if [ "$3" == "0" ]; then exit; fi

BRANCH_NAME=$(git symbolic-ref --short -q HEAD)
NUM_CHECKOUTS=`git reflog --date=local | grep -o ${BRANCH_NAME} | wc -l`

#if the refs of the previous and new heads are the same.
#AND the number of checkouts equals one, a new branch has been created
# UNLESS a branch with the same name has been created previously.
if [ "$1" == "$2"  ] && [ ${NUM_CHECKOUTS} -eq 1 ]; then
    pwsh "./GitHooks/CreateBranchHook.ps1"
fi
'@

$LegacyCreateBranchHookScriptPath = './CreateBranchHook.ps1'
$CreateBranchHookScriptPath = './GitHooks/CreateBranchHook.ps1'
$CreateBranchHookScript = @'
# This file was written by deploy-database-git-scripts.ps1

<#
.DESCRIPTION
Finds a file located within the VS root dir
copy/past of FindMSPath in the database project
#>
function FindFile([string] $CurrentDirectory, $TargetFileName, $InitialSearchLocation = "$((get-location).Drive.Name):\") {
    if (-not (Test-Path $InitialSearchLocation)) {
        $null
        return
    }
    #Write-Host "Searching for [$TargetFileName] starting in [$InitialSearchLocation]..."
    $parentDir = $InitialSearchLocation
    Set-Location $parentDir
    # This junk just pertains to msbuild, but it doesn't hurt other searches.
    # We have to exclude the forking amd version of msbuild. -Exclude doesn't work.  -notcontains does not work.
    $result = Get-ChildItem -Include $TargetFileName -Attributes !Hidden, !System, !ReparsePoint -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notlike '*amd64*' }

    Set-Location $CurrentDirectory > $null # Set back to original location.

    if ($null -eq $result) {
        $null
        return # Would be _nice_ if Test-Path didn't crash on null
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
        $null
    }

}

<#
.DESCRIPTION
Build the sqlproj; return message.
#>
function BuildDacpac($msBuildPath, $sqlProjPath) {
    $sqlProjDirectory = $sqlProjPath | Split-Path
    $dacpacPath = Resolve-Path "$sqlProjDirectory/*.dacpac" # get full path; null if not found.
    if (($null -ne $dacpacPath) -and (Test-Path $dacpacPath)) {
        Remove-Item $dacpacPath # remove any pre-existing
    }
    # beeld
    . $msBuildPath $sqlProjPath -consoleloggerparameters:'ErrorsOnly;NoSummary' -property:'OutDir=.;DebugType=None' # exclude pdb, outdir is relative to project file.
    $dacpacPath = Resolve-Path "$sqlProjDirectory/*.dacpac"
    if ($null -eq $dacpacPath) {
        'Unable to find database project build output.' # build must've failed.
    } else {
        $projectName = $dacpacPath | Split-Path -LeafBase # file name portion only.  This will equal the project name.
        $dllPath = Join-Path $sqlProjDirectory "$projectName.dll" # base of sql project path plus project name plus dll
        if (Test-Path $dllPath) { # delete the dll if present (if we're here it darn well should be)
            Remove-Item $dllPath
        }
        $finalDacpacName = Join-Path $sqlProjDirectory 'databaseState.dacpac'
        Rename-Item $dacpacPath $finalDacpacName
        'Database state set.'
    }
}

<#
.DESCRIPTION
Try default, then less targeted attempt at finding msbuild.  It never seems to be on the path like normal useful executables.
#>
function FindMSBuildPath {
    # Default MSBuild path
    $result = 'C:\Program Files (x86)\Microsoft Visual Studio\2019\Professional\MSBuild\Current\Bin\MSBuild.exe'
    if (-not (Test-Path $result)) {
        $result = FindFile (Get-Location).Path 'msbuild.exe' 'C:\Program Files (x86)\Microsoft Visual Studio'
        if (-not (Test-Path $result)) {
            $result = FindFile (Get-Location).Path 'msbuild.exe' ${env:ProgramFiles(x86)}
            if (-not (Test-Path $result)) {
                $result = FindFile (Get-Location).Path 'msbuild.exe' # root
            }
        }
    }
    $result
}

# FOR TESTING ONLY
#Set-Location 'your repo root'

Write-Host '--Setting database project state for potential database changes--'
Write-Host 'Searching for msbuild...  If this is taking a long time, search for "Default MSBuild path" to set a default.'
$msBuildPath = FindMSBuildPath
if ($null -ne $msBuildPath) {
    $sqlProjSearchRoot = (Get-Location).Path # Set to actual parent dir to speed this up.
    Write-Host 'Searching for sqlproj...  If you want to speed this up, search for "sqlProjSearchRoot."'
    $sqlProjFilePath = FindFile (Get-Location).Path '*.sqlproj' $sqlProjSearchRoot
    if ($null -ne $sqlProjFilePath) {
        Write-Host 'Found sqlproj'
        Write-Host 'Building database project...'
        BuildDacpac $msBuildPath $sqlProjFilePath | Write-Host
    } else {
        Write-Host "Unable to set database state: can't find sqlproj file" -ForegroundColor Red
    }
} else {
    Write-Host "Unable to set database state: can't find msbuild" -ForegroundColor Red
}
'@

function EnsureInsideRepo {
    if ($null -eq (Get-ChildItem -Directory '.git')) {
        Write-Host "It doesn't look like you're in a git repo." -ForegroundColor Red
        Exit
    }
}

<#
.DESCRIPTION
Remove $line (entire) from file at $path
#>
function RemoveLine($line, $path) {
    if (Test-Path $path) {
        (Get-Content -Path $path) | Where-Object { $_ -ne $line } | Set-Content -Path $path
    }
}

<#
.DESCRIPTION
Add content to the beginning of a config file.
#>
function AddConfigFileEntry($configFilePath, $content) {
    if (Test-Path $configFilePath) {
        $existingContent = Get-Content -Path $configFilePath -Delimiter '\0'
    }
    if ($null -eq $existingContent) {
        # add the file; it doesn't exist (common for no .gitattributes)
        Set-Content -Path $configFilePath $content
        Return
    }
    if (-not ($existingContent.Contains($content))) {
        # Add to head of file
        Set-Content -Path $configFilePath "$content$([System.Environment]::NewLine)$existingContent"
    }
}

<#
.DESCRIPTION
Create the hook script that is invoked upon branch creation.
#>
function WriteBranchHookScript {
    if (Test-Path $LegacyCreateBranchHookScriptPath) {
        Remove-Item $LegacyCreateBranchHookScriptPath
    }
    Set-Content -Path $CreateBranchHookScriptPath $CreateBranchHookScript
}

RemoveLine '*.resources merge=database-resource-script-merge-driver' '.gitattributes' # remove previously configured merge driver if present

# Assume this script is running from repo root/GitHooks; set location to parent (back to root).
Set-Location (Get-Item $PSCommandPath).Directory.Parent.FullName

# These might fail
EnsureInsideRepo
# Add the branch hook file (the part that triggers the hook when creating a new branch; not the actual hook script) at the root of the repo.
# Overwrite any previous version.
Set-Content -Path $CreateBranchHookPath $CreateBranchHook

AddConfigFileEntry $GitIgnorePath $GitIgnoreContent
WriteBranchHookScript

Write-Host 'Git configured.'