############################################## WARNING!! EVERYTHING HEREIN MUST BE IDEMPOTENT!!

Set-Location (Get-Item $PSCommandPath).DirectoryName # ensure current dir is this script location.

Import-Module './AddNodesToDatabaseProj.psm1'
Import-Module './AddRuntimeScriptsAsIgnoredToServiceProject.psm1'
Import-Module './GeneralProjectBasedScripts.psm1'
Import-Module './UpdateConfigurationItemsInPS.psm1'
Import-Module './CommitJournalScript.psm1'

# Assumption: the goods are all in the same directory as this script
$migrationsJournalScriptPath = ".\1.sql"
$commitFilePath = '.\CommitDatabaseScripts.ps1'
$commonFilePath = '.\Common.psm1'
$compareFilePath = '.\UpdateProject.scmp'
$extractResourceScriptsFilePath = '.\ExtractResourceScripts.ps1'
$generateMigrationScriptFilePath = '.\GenerateMigrationScript.ps1'
$updateDatabaseStateFileFilePath = '.\UpdateDatabaseStateFile.ps1'
$detectChangesPath = '.\DetectChanges.psm1'
$gitHooksDir = '.\GitHooks'
$originalReadmeFilePath = '.\README.MD'
$finalReadMeFilePath = '.\DatabaseMigrator_README.MD'
$runtimeScriptsDir = ''

Write-Host 'Initial checks...' -ForegroundColor Green
$currentScriptDir = (Get-Item $PSCommandPath).DirectoryName
$slnDir = GetSolutionDir $currentScriptDir
if ($null -eq $slnDir) {
    Write-Host 'Unable to find .sln in this directory or any parent' -ForegroundColor Red
    exit
}
EnsureInsideRepo $slnDir

Write-Host 'Ensuring database project present.' -ForegroundColor Green
$databaseProjectFilePath = GetProjectPath $slnDir '.sqlproj'
if ($null -eq $databaseProjectFilePath) {
    Write-Host "Unable to find a database project under [$slnDir]" -ForegroundColor Red
    exit
}

# Service project should be what we are under.
# We should be in a subdir; initial ReadMe instructs that way.
Write-Host 'Configuring service project.' -ForegroundColor Green
$serviceProjectSearchRoot = $currentScriptDir | Split-Path -Parent
$serviceProjectFilePath = GetProjectPath $serviceProjectSearchRoot '.csproj'
if ($null -eq $serviceProjectFilePath) {
    Write-Host "Expected to find .csproj under [$serviceProjectSearchRoot]" -ForegroundColor Red
    exit
}
if ($serviceProjectFilePath -is [Array]) {
  Write-Host "Expected to find .csproj under [$serviceProjectSearchRoot] but found multiple paths.  Is this folder not under your service project?" -ForegroundColor Red
  exit
}
try {
    AddRuntimeScriptsProjectReference $serviceProjectFilePath
    $serviceProjectRootPath = ($serviceProjectFilePath | Split-Path)  # absolute
    $runtimeScriptsDir = "$serviceProjectRootPath\DatabaseMigration\RuntimeScripts"
    # force: create if not present
    mkdir -Force $runtimeScriptsDir > $null
}
catch {
    Write-Host "Error configuring runtime scripts directory: $_" -ForegroundColor Red
    exit
}

Write-Host 'Replacing references in core powershell files' -ForegroundColor Green
$serviceProjectFileName = Split-Path -Leaf $serviceProjectFilePath
$relativeServiceProjectRootPath = AbsoluteToRelative $slnDir $serviceProjectRootPath
$DatabaseProjectName = Split-Path -LeafBase $databaseProjectFilePath
try {
    ReplaceText $commitFilePath 'DatabaseMigration.csproj' $serviceProjectFileName
    ReplaceText $commonFilePath "global:DatabaseProjectName = ''" "global:DatabaseProjectName = '$DatabaseProjectName'"
    ReplaceText $commonFilePath "global:DatabaseMigrationRoot = '/DatabaseMigration" "global:DatabaseMigrationRoot = '$relativeServiceProjectRootPath"
    ReplaceText $originalReadmeFilePath 'MigrationDatabase' $DatabaseProjectName
}
catch {
    Write-Host "Error replacing text in core powershell scripts: $_" -ForegroundColor Red
    exit
}

Write-Host 'Moving items under database project.' -ForegroundColor Green
$databaseProjectRootDir = $databaseProjectFilePath | Split-Path -Parent
try {
    # Unfortunately, we can't just iterate over all ps scripts in current dir because there are config scripts bundled with actual system scripts (see pre-build.ps1)
    # If you add new here, you must also add in AddDatabaseProjectItems
    # overwrite except $compareFilePath; they may have customized this.
    Copy-Item -Force $commitFilePath "$databaseProjectRootDir\$(Split-Path -Leaf $commitFilePath)"
    Copy-Item -Force $commonFilePath "$databaseProjectRootDir\$(Split-Path -Leaf $commonFilePath)"
    $compareFileDestinationPath = "$databaseProjectRootDir\$(Split-Path -Leaf $compareFilePath)"
    if (-not (Test-Path $compareFileDestinationPath))
    {
        Copy-Item $compareFilePath $compareFileDestinationPath
    }
    Copy-Item -Force $extractResourceScriptsFilePath "$databaseProjectRootDir\$(Split-Path -Leaf $extractResourceScriptsFilePath)"
    Copy-Item -Force $generateMigrationScriptFilePath "$databaseProjectRootDir\$(Split-Path -Leaf $generateMigrationScriptFilePath)"
    Copy-Item -Force $updateDatabaseStateFileFilePath "$databaseProjectRootDir\$(Split-Path -Leaf $updateDatabaseStateFileFilePath)"
    Copy-Item -Force $detectChangesPath "$databaseProjectRootDir\$(Split-Path -Leaf $detectChangesPath)"
}
catch {
    Write-Host "Error copying files under database project: $_" -ForegroundColor Red
    exit
}

# Also adds references to the root level files (powershell files & compare file)
Write-Host 'Adding scripts and folders and their project references to the database project.' -ForegroundColor Green
try {
    AddDatabaseProjectItems $databaseProjectFilePath
}
catch {
    Write-Host "Error adding items to database project file: $_" -ForegroundColor Red
    exit
}

$firstScriptDestPath = "$runtimeScriptsDir\1.sql"
if (-not (Test-Path $firstScriptDestPath)) { # assume if it's there, it has already been committed.
    Write-Host 'Committing MigrationsJournal script as 1.sql.' -ForegroundColor Green
    if (-not (CommitScriptAsResource $migrationsJournalScriptPath $runtimeScriptsDir $serviceProjectFilePath)) {
        exit
    }
} else {
  # Local copy of migration table script may be old
  Copy-Item -Force $migrationsJournalScriptPath $firstScriptDestPath
}

Write-Host 'Adding git hooks.' -ForegroundColor Green
$gitHooksDirDestPath = "$slnDir\GitHooks"
if (Test-Path $gitHooksDirDestPath) {
    Remove-Item $gitHooksDirDestPath -Recurse
}
Copy-Item -Force $gitHooksDir $gitHooksDirDestPath -Recurse
########################## Call script to deploy git scripts
& "$gitHooksDirDestPath\deploy-database-git-scripts.ps1"

# GOL: above script will change current directory, must reset to this script location.
Set-Location (Get-Item $PSCommandPath).DirectoryName

if (-not (Test-Path $finalReadMeFilePath)) {
    Copy-Item $originalReadmeFilePath $finalReadMeFilePath
}

Write-Host "Configuration complete; you should probably delete this folder." -ForegroundColor Yellow