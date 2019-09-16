<#
function FindScriptInProjectItems($databaseProjectItem, $scriptName) {
  $result = $databaseProjectItem | Select-Object -Expand ProjectItems | Where-Object { $_.Name -eq 'Scripts' -or $_.Name -eq 'AdHoc' -or $_.Name -eq $scriptName }
  if ($result.Name -eq $scriptName) {
    $result
  }
  if ($null -ne $result) {
    FindScriptInProjectItems $result $scriptName
  }
  # else we didn't find it.
}

$databaseProjectObject = $dte.Solution.Projects | Where-Object { $_.Name -eq 'MigrationDatabase' }
$scriptProjectItem = FindScriptInProjectItems $databaseProjectObject 'Script1.sql'
$scriptProjectItem.Remove()
#>
