Import-Module "$PSScriptRoot\Common.psm1" #-Force

<#
.DESCRIPTION
Uses sqlpackage to generate a diff report between dacpac created upon branch creation and current database state.
This is intended to be called when someone adds an ad-hoc script (not a migration script) to serve as a check/reminder of the differences that
may exist between the state at the beginning of the branch and current.
The user may then realize that his/her ad-hoc script missed something, or may see a pre-existing difference such that the database project should be updated.
Pre: Initial state dacpac should've been created upon branch creation.
Examples:
1) Ad-Hoc
  • Change made to local database directly.
  • User prefers to commit ad-hoc script for change, forgetting to update database project.  This will remind user.
2) Ad-Hoc
  • Database project was out of sync with database upon branch creation from prior action.
  • User commits ad-hoc script that may not even modify schema.  This will illuminate user about lingering change.
3) Generated Script
  • Database project was out of sync with database upon branch creation from prior action.
  • User makes changes, generates a migration script (after updating database project), commits.
  • User has done everything correctly, but there was lingering change.  This will illuminate user about lingering change.
4) Generated Script
  • Database project was good upon branch creation.
  • User makes schema changes directly in the database project intending to apply those changes locally upon next run of service (probably rare)
  • Upon commit, user is made aware that change hasn't been applied.
  • This may annoy, but in any case will confirm the changes that have yet to be applied to the local database.
#>
function GenerateDiffReport {
  if (-not (TestConnection)) {
    Write-Host 'Attempting to generate diff report, local connection failed using configured $global:conStr' -ForegroundColor Red
    exit
  }

  $InitialHostLocation = Get-Location
  try {
    BuildDacpac #If we just committed, but never generated a script (as in, added an ad-hoc script), we will need to build so the comparison below reflects what's in the database project now.
    FindExecutables

    if (TestExecutablePaths) {
      # target should be the dacpac state as of branch creation or manual run of UpdateDatabaseStateFile.ps1.
      Write-Host "Generating diff report between [$global:TargetDacPath] and local database." -ForegroundColor DarkGreen
      $diffOutputPath = [System.IO.Path]::GetTempFileName()

      try {
        & $global:SQLPackagePath /Action:DeployReport /p:DropObjectsNotInSource=True /p:ExcludeObjectTypes='Credentials;DatabaseScopedCredentials;Users;Logins;RoleMembership;Permissions' /SourceFile:"$global:SourceDacPath" /TargetServerName:"$(GetServerName)" /OutputPath:"$diffOutputPath" /TargetDatabaseName:$global:DatabaseProjectName
        ShowDiffResults $diffOutputPath
      }
      finally {
        [System.IO.File]::Delete($diffOutputPath)
      }

    } else {
      Write-Host 'Failed to find executable for generating diff report.  This report is used to warn of possible out-of-sync database project state.' -ForegroundColor Red
    }
  }
  catch {
    Write-Host "Error attempting to compare current state with database state: $_" -ForegroundColor Red
    exit # Without this the script may keep going
  }
  finally {
    Set-Location $InitialHostLocation > $null # reset location
  }
}

function GetServerName {
  try {
    $x = New-Object System.Data.SqlClient.SqlConnectionStringBuilder($global:conStr)
    $x.DataSource
  }
  catch {
    ''
  }
}

<#
.DESCRIPTION
Extracts operations out of xml file generated by sqlpackage.exe /Action:"DeployReport"
Returns list of strings like "Alter [dbo].[Table1]"
#>
function ExtractDeployOperations([string] $deployReportPath) {
    $result = @()
    $doc = New-Object -TypeName 'System.Xml.XmlDocument'
    $ns = New-Object -TypeName 'System.Xml.XmlNamespaceManager' -ArgumentList @($doc.NameTable) #xml worthless bullshit
    $ns.AddNamespace('x', 'http://schemas.microsoft.com/sqlserver/dac/DeployReport/2012/02')
    $doc.Load($deployReportPath)
    $nodes = $doc.SelectNodes('//x:Operation', $ns)
    $nodes | ForEach-Object {
        $operationName = $_.Attributes[0].Value
        $_.ChildNodes | ForEach-Object {
            $result += "$operationName $($_.Attributes[0].Value)"
        }
    }
    $result
}

<#
.DESCRIPTION
$diffOutputPath expected to have been generated.
#>
function ShowDiffResults($diffOutputPath) {
  if ((Test-Path $diffOutputPath) -ne $true) {
      Write-Host "Failed to create diff report.  See GenerateDiffReport.  Diff report not required, but helpful." -ForegroundColor Red
  } else {
    $operations = ExtractDeployOperations $diffOutputPath
    if ($operations.Length -eq 0) {
      Write-Host 'No additional (missing) database schema operations detected.'
    } else {
      Write-Host 'The following operations represent a diff between current database state and database project state.' -ForegroundColor Red
      Write-Host 'This may be expected, e.g., you updated the database project, generated a script and have yet to apply it locally.' -ForegroundColor Red
      Write-Host 'More likely, it indicates these changes need to be applied to the database project.' -ForegroundColor Red
      Write-Host $operations
    }
  }
}

function TestConnection {
  try {
    $con = GetOpenConnection
    $con.Dispose() > $null
    $true
  }
  catch {
    $false
  }
}
