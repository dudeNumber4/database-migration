# Holdover script from when scripts lived in a resource file, but it doesn't hurt to keep around.
# Writes out the scripts and their content to a database table.

Import-Module "$PSScriptRoot\Common.psm1" #-Force

$global:TempResourceOutputTableName = 'ResourceScripts'
$global:CreateTempResourceOutputTable = "drop table if exists $global:TempResourceOutputTableName; create table $global:TempResourceOutputTableName(id int, Script varchar(max))"

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
        # similar to GetNextScriptNumber.  Skip first script (that creates journal table).
        Get-ChildItem -Path $global:ResourceFolderPath -File | Where-Object { $_.BaseName -ne '1' } | ForEach-Object {
            $scriptContent = (GetScriptContent $_.FullName) -replace "'", "''" # escape ticks so the statement will complete
            $con = GetOpenConnection
            $cmd = GetCommand $con "insert $global:TempResourceOutputTableName values($($_.BaseName), '$scriptContent')"
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
CreateTempTable
WriteResourcesToTable