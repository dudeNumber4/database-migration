# Holdover script from when scripts lived in a resource file, but it doesn't hurt to keep around.
# Writes out the scripts and their content to a database table.

Import-Module "$PSScriptRoot\Common.psm1"

$global:TempResourceOutputTableName = 'ResourceScripts'
$global:CreateTempResourceOutputTable = "drop table if exists $global:TempResourceOutputTableName; create table $global:TempResourceOutputTableName(id int, Script varchar(max))"
$global:conStr = ''

# Caller must close the connection
function GetOpenConnection() {
    try {
        $result = New-Object System.Data.SqlClient.SqlConnection
        $result.ConnectionString = $global:conStr
        $result.Open()
        $result
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
}

# Assumes open connection
function GetCommand([System.Data.SqlClient.SqlConnection] $con, [string] $cmdText) {
    $result = New-Object System.Data.SqlClient.SqlCommand
    $result.CommandText = $cmdText
    $result.Connection = $con
    $result
}

function CreateTempTable {
    Write-Host 'Creating temp table' -ForegroundColor DarkGreen
    $con = GetOpenConnection
    try {
        $cmd = GetCommand $con $global:CreateTempResourceOutputTable
        $cmd.ExecuteNonQuery() > $null
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit # Without this the script may keep going
    }
    finally {
        $cmd.Dispose() > $null
        $con.Dispose() > $null
    }
}

function WriteResourcesToTable {
    Write-Host "Extracting script resources from [$global:ResourceFolderPath] to temp table [$global:TempResourceOutputTableName]" -ForegroundColor DarkGreen
    try {
        # similar to GetNextScriptNumber
        Get-ChildItem -Path $global:ResourceFolderPath -File | ForEach-Object {
            $scriptContent = ($_ | GetScriptContent) -replace "'", "''" # escape ticks so the statement will complete
            $con = GetOpenConnection
            $cmd = GetCommand $con "insert $global:TempResourceOutputTableName values($($_.Key), '$scriptContent')"
            try {
                $cmd.ExecuteNonQuery() > $null
            }
            catch {
                Write-Host $_ -ForegroundColor Red
                exit
            }
            finally {
                $cmd.Dispose() > $null
                $con.Dispose() > $null
            }
        }
        Write-Host 'done' -ForegroundColor DarkGreen
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit
    }
}

EnsureDatabaseProjectSelected
SetProjectBasedGlobals
# :Configure: Adjust as necessary.  Assumes all devs can share same local connection string.
$global:conStr = "Server=.\SQLEXPRESS;Database=$global:DatabaseProjectName;Trusted_Connection=Yes"
CreateTempTable
WriteResourcesToTable