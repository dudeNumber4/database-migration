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
