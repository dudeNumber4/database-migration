############################################ Merge Driver
$GitConfigPath = './.git/config'
#This goes in the config file and tells git that there is a merge driver.
$MergeDriverConfigEntry = @'
[merge "database-resource-script-merge-driver"]
    name = Custom merge driver for database migration resource files
    driver = pwsh ./ResolveScriptResourceDifferences.ps1 %O %A %B
'@

# This entry tells git which file type our merge driver works on.
$GitAttributesPath = './.gitattributes'
$GitAttributesContent = '*.resources merge=database-resource-script-merge-driver'

# Add to gitignore database project files
$GitIgnorePath = './.gitignore'
$GitIgnoreContent = @'
# database project files
*.dbmdl
*.jfm
*.refactorlog
*.dacpac

'@

# The script referenced by the merge driver
$MergeDriverPath = './ResolveScriptResourceDifferences.ps1'
$MergeDriverContents = @'
# Incoming params
param([string] $ancestorPath, [string] $currentPath, [string] $otherPath)

$global:ancestorReader = $null
$global:currentReader = $null
$global:otherReader = $null
$global:tempWriter = $null
$global:maxScriptNumAncestor = 0
$global:maxScriptNumCurrent = 0
$global:maxScriptNumOther = 0
$global:tempWriterPath = "./temp.resources"
#
# Caller must clean up
function GetResourceWriter([string] $path) {
    New-Object System.Resources.ResourceWriter -ArgumentList $path
}

# Caller must clean up
function GetResourceReader([string] $path) {
    New-Object System.Resources.ResourceReader -ArgumentList $path
}

<#
.DESCRIPTION
Basically copy/paste from GetNextScriptKey in database project script CommitDatabaseScripts
#>
function GetMaxScriptKey([System.Resources.ResourceReader] $r) {
    $junkref = 0
    # Find the max of all keys where the key converts to int (which should be all)
    $max = ($r | Where-Object { [int]::TryParse($_.Key, [ref] $junkref) } | Select-Object -ExpandProperty Key | ForEach-Object { [System.Convert]::ToInt32($_) } | Measure-Object -Max).Maximum
    if ($null -eq $max) {
        $max = 0
    }
    $max
}

<#
.DESCRIPTION
Get the script at number $keyNum if present.  Result is null if not.
#>
function GetScriptByKeyNum([System.Resources.ResourceReader] $reader, [string] $keyNum) {
    # $keyNum is coerced.
    $reader | Where-Object { $_.Key -eq $keyNum } | Select-Object -ExpandProperty Value
}

<#
.Description
For case insensitive instances of "drop" found, e.g. "drop table bubba", return the 2 words after each instance as an entry in a hash table.
This actually wont work right if the 2 words after an instance of "drop" are the last words.  But were trying to catch the case where
an object is dropped, then created anyway.
#>
function GetDropObjectIdentifiers([string] $script) {
    $foundDrop = $false
    $wordCountAfterDrop = 0
    $wordsAfterDrop = @()
    $result = @{}
    
    -split $script | ForEach-Object {
        if ($_ -eq "drop") {
            $foundDrop = $true
            return #continue
        }
        if ($foundDrop) {
            if ($wordCountAfterDrop -lt 2) {
                $wordsAfterDrop += $_
                $wordCountAfterDrop += 1
            } else {
                $result[$result.Count] = $wordsAfterDrop
                $wordsAfterDrop = @()
                $wordCountAfterDrop = 0
                $foundDrop = $false;
            }
        }
    }

    $result
}

<#
.Description
Parameters are hash tables of arrays of string (result of call to GetDropObjectIdentifiers).
Return any array that are present in both (both strings match).
#>
function IntersectingDropObjects($dropObjects1, $dropObjects2) {
    $dropObjects1.GetEnumerator() | ForEach-Object {
        $dropObject1 = $_
        $dropObjects2.GetEnumerator() | ForEach-Object {
            if ( ($dropObject1.Value[0] -eq $_.Value[0]) -and ($dropObject1.Value[1] -eq $_.Value[1]) ) {
                $dropObject1
            }
        }
    }
}

<#
.DESCRIPTION
Get all the new drop objects (see GetDropObjectIdentifiers) for the current reader.
#>
function PopulateDropObjectsFor([System.Resources.ResourceReader] $resourceReader, $maxScriptNum) {
    $result = @{}
    $global:maxScriptNumAncestor..$maxScriptNum | ForEach-Object {
        $result += GetDropObjectIdentifiers (GetScriptByKeyNum $resourceReader $_)
    }
    $result
}

<#
.DESCRIPTION
Ensure current and other arent re-creating the same object (both contain "drop <ObjectType> <ObjectName>").
#>
function EnsureNoConflictingDropObjectsExist {
    $dropObjectsCurrent = PopulateDropObjectsFor $global:currentReader $global:maxScriptNumCurrent
    $dropObjectsOther = PopulateDropObjectsFor $global:otherReader $global:maxScriptNumOther
    $intersection = IntersectingDropObjects $dropObjectsCurrent $dropObjectsOther
    if ($null -ne $intersection) {
        Write-Host "Conflicting scripts found while attempting to merge a database script resource file (2 scripts seem to be recreating the same object).  Conflict indication: [drop $($intersection.Value[0]) $($intersection.Value[1])]$(ManualMergeNeededCheckReadMe)" -ForegroundColor Red
        Exit 1
    }
}

<#
.DESCRIPTION
Ensure the file were dealing with is one of ours by checking that the script #1 contains an expected hard coded string.
#>
function EnsureMigrationResourceFile {
    $foundationalScript = GetScriptByKeyNum $global:ancestorReader "1"
    if (-not (($null -ne $foundationalScript) -and ($foundationalScript -like "*create table*"))) {
        Write-Host "Error during merge of .resource files: the file to be merged doesn''t seem to be a database migrator resource script file." -ForegroundColor Red
        Exit 1
    }
}

<#
.DESCRIPTION
Historical scripts can only be modified by one branch; not both.
#>
function MergeHistoricalScript($scriptNum, $ancestorScript, $otherScript, $currentScript) {
    if ($otherScript -eq $currentScript) {
        $currentScript # Both branches agree (may or may not have diverged from ancestor; doesnt matter); take it.
    } else {
        $otherEqualsAncestor = $otherScript -eq $ancestorScript
        $currentEqualsAncestor = $currentScript -eq $ancestorScript
        if ($otherEqualsAncestor -and (-not $currentEqualsAncestor)) {
            $currentScript # current has modified; take it.
        } elseif ($currentEqualsAncestor -and (-not $otherEqualsAncestor)) {
            $otherScript # other has modified; take it.
        } else {
            Write-Host "Both branches being merged have modified an historical script.  Script number: $scriptNum.$(ManualMergeNeededCheckReadMe)" -ForegroundColor Red
            Exit 1
        }
    }
}

<#
.DESCRIPTION
Add historical entries from the three branches ensuring they will merge correctly.
Pre: EnsureBothBranchesContainHistory has been called.
#>
function AddHistory() {
    1..$global:maxScriptNumAncestor | ForEach-Object {
        $ancestorScript = GetScriptByKeyNum $global:ancestorReader $_ # current number coerced to string
        $otherScript = GetScriptByKeyNum $global:otherReader $_
        $currentScript = GetScriptByKeyNum $global:currentReader $_
        if (($null -eq $ancestorScript) -or ($null -eq $otherScript) -or ($null -eq $currentScript)) {
            Write-Host "While attempting to merge historical scripts in the database script resource file, found a null/missing script.  Script number: $_." -ForegroundColor Red
            Exit 1
        }
        if ($_ -eq 1) {
            if (-not ($ancestorScript -eq $otherScript -eq $currentScript)) {
                Write-Host "While attempting to merge historical scripts in the database script resource file, found that foundational script (script #1) has been modified.  This script must remain unmodified." -ForegroundColor Red
                Exit 1
            }
        }
        $script = MergeHistoricalScript $_ $ancestorScript $otherScript $currentScript
        #Write-Host "Adding historical script [$script] as number $_"
        $global:tempWriter.AddResource($_, $script)
    }
}

<#
.DESCRIPTION
Both branches must contain all of whats in ancestor.  One or the other may have modified a given script in that list, but they all must be there.
#>
function EnsureBothBranchesContainHistory {
    #Write-Host "EnsureBothBranchesContainHistory, maxScriptNumAncestor: $global:maxScriptNumAncestor, maxScriptNumCurrent: $global:maxScriptNumCurrent, maxScriptNumOther: $global:maxScriptNumOther"
    if (-not (($global:maxScriptNumOther -ge $global:maxScriptNumAncestor) -and ($global:maxScriptNumCurrent -ge $global:maxScriptNumAncestor))) {
        Write-Host "Expected at least $global:maxScriptNumAncestor historical scripts to be in current branch and branch being merged.  Found $global:maxScriptNumCurrent in current branch; $global:maxScriptNumOther in other branch." -ForegroundColor Red
        Exit 1
    }    
}    

<#
.DESCRIPTION
Add the entries from other than ancestor (those that follow whats in ancestor) into temp file.
Pre: AddHistory has been called, temp resource file has been created.
Returns: Count of scripts added
#>
function AddEntriesFrom([int] $offset, [System.Resources.ResourceReader] $reader, $maxScriptNumCurrentResource) {
    if ($maxScriptNumCurrentResource -gt $global:maxScriptNumAncestor) { # if any new
        ($global:maxScriptNumAncestor + 1)..$maxScriptNumCurrentResource | ForEach-Object {
            $script = GetScriptByKeyNum $reader $_
            #Write-Host "Adding new script [$script] as number $($_ + $offset)"
            $global:tempWriter.AddResource($_ + $offset, $script)
        }
        $maxScriptNumCurrentResource - $global:maxScriptNumAncestor
    }
}

<#
.DESCRIPTION
Add new entries from both branches.
Pre: AddHistory has been called.
#>
function AddNewResources {
    # Add everything in other followed by everything in current.
    $countScriptsAdded = AddEntriesFrom 0 $global:otherReader $global:maxScriptNumOther
    $countScriptsAdded = AddEntriesFrom $countScriptsAdded $global:currentReader $global:maxScriptNumCurrent
}

function PopulateFinalMerge {
    # Overwrite current (the final file) with contents of temp
    $global:currentReader.Close() > $null # so we can overwrite it
    Remove-Item $currentPath
    Copy-Item $global:tempWriterPath -Destination $currentPath
}

function FileCleanup {
    if (Test-Path $global:tempWriterPath) {
        Remove-Item $global:tempWriterPath
    }

    #$mergeCommentPath = "./.git/MERGE_MSG" # this @#$%er cant be mucked with during merge; requires crappy environment variable.
    $mergeMsgSwapPath = "./.git/.MERGE_MSG.swp"

    # Mea Culpa.  Ive no clue what better to do here.  Git will report a _newer_ copy of this file exists if I dont do this.
    if (Test-Path $mergeMsgSwapPath) {
        Remove-Item $mergeMsgSwapPath
    }
}

<#
.DESCRIPTION
Tacks on additional instructions for when user just needs to do manual merge (not total failure).
#>
function ManualMergeNeededCheckReadMe {
    "$([System.Environment]::NewLine)These scripts in the .resource file must be merged manually.  See database migrator ReadMe."
}

#######    MAIN
$global:ancestorReader = GetResourceReader $ancestorPath
$global:otherReader = GetResourceReader $otherPath
$global:currentReader = GetResourceReader $currentPath
$global:maxScriptNumAncestor = GetMaxScriptKey $ancestorReader
$global:maxScriptNumCurrent = GetMaxScriptKey $currentReader
$global:maxScriptNumOther = GetMaxScriptKey $otherReader

try {
    EnsureMigrationResourceFile
    EnsureBothBranchesContainHistory
    EnsureNoConflictingDropObjectsExist
    $global:tempWriter = GetResourceWriter $global:tempWriterPath
    try {
        AddHistory
        AddNewResources
    }
    finally {
        $global:tempWriter.Close() > $null
    }
    PopulateFinalMerge
    Exit 0 # Pass
}
catch {
    Write-Host "Error during merge of script files: $_$(ManualMergeNeededCheckReadMe)" -ForegroundColor Red
    Exit 1 # Fail
}
finally {
    FileCleanup
    if ($null -ne $global:ancestorReader) {
        $global:ancestorReader.Close() > $null
    }
    if ($null -ne $global:otherReader) {
        $global:otherReader.Close() > $null
    }
    if ($null -ne $global:currentReader) {
        $global:currentReader.Close() > $null
    }
}
'@

############################################ Create Branch Hook
$CreateBranchHookPath = './.git/hooks/post-checkout'
$CreateBranchHook = @'
#!/bin/bash

# this is a file checkout – do nothing
if [ "$3" == "0" ]; then exit; fi

BRANCH_NAME=$(git symbolic-ref --short -q HEAD)
NUM_CHECKOUTS=`git reflog --date=local | grep -o ${BRANCH_NAME} | wc -l`

#if the refs of the previous and new heads are the same.
#AND the number of checkouts equals one, a new branch has been created
# UNLESS a branch with the same name has been created previously.
if [ "$1" == "$2"  ] && [ ${NUM_CHECKOUTS} -eq 1 ]; then
    pwsh "./CreateBranchHook.ps1"
fi
'@

$CreateBranchHookScriptPath = './CreateBranchHook.ps1'
$CreateBranchHookScript = @'
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

# not complete
function AddBranchHook {
    if (Test-Path $CreateBranchHookPath) {
        $existingContent = Get-Content -Path $CreateBranchHookPath -Delimiter '\0'
    }
    if ($null -eq $existingContent) {
        # add the file; it doesn't exist
        Set-Content -Path $CreateBranchHookPath $CreateBranchHook
        Return
    }
    if (-not ($existingContent.Contains($CreateBranchHook))) {
        # The have an existing hook (rare); we ain't gonna parse it.
        Write-Host "Found an existing hook ($CreateBranchHookPath).  Unable to add our version.  The 2 hooks would have to be manually combined.  Check the contents of this script." -ForegroundColor Red
        Exit
    }
}

# Assume this script is running from repo root; set location there
Set-Location ($PSCommandPath | Split-Path)

# These might fail
EnsureInsideRepo
AddBranchHook

AddConfigFileEntry $GitConfigPath $MergeDriverConfigEntry
AddConfigFileEntry $GitAttributesPath $GitAttributesContent
AddConfigFileEntry $GitIgnorePath $GitIgnoreContent

# Write out script
Set-Content -Path $MergeDriverPath $MergeDriverContents
Set-Content -Path $CreateBranchHookScriptPath $CreateBranchHookScript

Write-Host 'Git configured.'