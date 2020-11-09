# Here are the replacements.
# The 3 instances below show how they appear by default in the ps file.
# $global:ServiceProjFilePath = "$global:DatabaseMigrationRoot\..\DatabaseMigration.csproj"
#       --> Replace 'DatabaseMigration.csproj' with result of call to GetServiceProjectName
# $global:DatabaseProjectName = ''
#       --> Replace '' with result of call to GetSqlProjectName
# $global:DatabaseMigrationRoot = '/DatabaseMigration/DatabaseMigration'
#       --> Replace '/DatabaseMigration with '/ + result of call to GetServiceProjectName

#$commitFilePath = 'C:\temp\DatabaseMigration\CommitDatabaseScripts.ps1'
#$commonFilePath = 'C:\temp\DatabaseMigration\Common.psm1'
#$serviceProjectFileName = 'ServiceProj.csproj'
#$serviceProjectName = 'ServiceProj'
#$DatabaseProjectName = 'DatabaseProj'

function ReplaceText([string] $path, [string] $text, [string] $replacement) {
    $existingText = (Get-Content -Path $path)
    $replacmentText = ($existingText -replace $text, $replacement)
    Set-Content -Path $path -Value $replacmentText
}

## WARNING! Don't ever put $ in a search string!
# Here are the 3 replacment calls that represent the replacements to be done at the top of this file.
#ReplaceText $commitFilePath 'DatabaseMigration.csproj' $serviceProjectFileName
#ReplaceText $commonFilePath "global:DatabaseProjectName = ''" "global:DatabaseProjectName = '$DatabaseProjectName'"
#ReplaceText $commonFilePath "global:DatabaseMigrationRoot = '/DatabaseMigration" "global:DatabaseMigrationRoot = '/$serviceProjectName"
#ReplaceText '.\README.md' 'MigrationDatabase' $DatabaseProjectName
