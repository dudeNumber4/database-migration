Import-Module "$PSScriptRoot\Common.psm1"

# Update database state as separate operation
EnsureDatabaseProjectSelected
SetProjectBasedGlobals
BuildDacpac
UpdateDatabaseStateDacPac
