<#
.DESCRIPTION
Look for .git in solution root or children
#>
function EnsureInsideRepo([string] $solutionRoot) {
    $resetDir = (Get-Item $PSCommandPath).DirectoryName # Ensure current dir is not changed as result of this function.
    Set-Location $solutionRoot # I couldn't see any way to tell Get-ChildItem to start looking at a given dir.
    if ($null -eq (Get-ChildItem -Directory '.git')) {
        Set-Location $resetDir
        Write-Host "It doesn't look like you're in a git repo." -ForegroundColor Red
        Exit
    }
    Set-Location $resetDir
}

<#
.DESCRIPTION
Starting at $startingPath, look for a path to a .sln, working way up to root.  Null if not found.
#>
function GetSolutionDir([string] $startingPath) 
{
    $potentialSolutionDir = $null
    $workingPath = $startingPath
    while ($null -eq $potentialSolutionDir) {
        if ($workingPath -eq '') {
            return
        }
        $potentialSolutionDir = ((Get-Childitem –Path $workingPath) | Where-Object { $_.FullName.EndsWith('.sln') }).DirectoryName
        $workingPath = Split-Path -Parent $workingPath
    }
    $potentialSolutionDir
}

<#
.DESCRIPTION
projExtension: .sqlproj, .csproj, etc.
Searches downward / Returns full path to project file.
#>
function GetProjectPath([string] $root, [string] $projExtension) {
    Get-Childitem –Path $root -File -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Extension -eq $projExtension } | Select-Object -ExpandProperty 'FullName'
}

<#
.DESCRIPTION
Given an $absoluteChild that is a subdirectory of $absoluteParent, return relative path from parent to child
Ex:
Parent: C:\source\database-migration
Child:  C:\source\database-migration\database-migration\MigrationDatabase
Result: /database-migration/MigrationDatabase
#>
function AbsoluteToRelative([string] $absoluteParent, [string] $absoluteChild) {
    $absoluteParent = $absoluteParent.Replace('/', '\') # normalize
    $absoluteChild = $absoluteChild.Replace('/', '\') # normalize
    $absoluteParent = $absoluteParent.EndsWith('\') ? $absoluteParent.Substring(0, $absoluteParent.Length -1) : $absoluteParent # remove trailing
    $absoluteChild = $absoluteChild.EndsWith('\') ? $absoluteChild.Substring(0, $absoluteChild.Length -1) : $absoluteChild # remove trailing
    $parent = $absoluteChild
    $segments = ''
    while (-not [System.String]::IsNullOrEmpty($parent)) {
        $segment = Split-Path -Leaf $parent
        $segments = ($segments -eq '') ? $segment : "$segment\$segments"
        if ((Join-Path $absoluteParent $segments) -eq $absoluteChild) {
            break
        }
        $parent = Split-Path -Parent $parent
    }
    "\$segments"
}
