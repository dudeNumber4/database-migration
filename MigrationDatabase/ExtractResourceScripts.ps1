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
    Write-Host 'Creating temp table' -ForegroundColor Blue
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
    Write-Host "Extracting script resources from [$global:ResourceFilePath] to temp table [$global:TempResourceOutputTableName]" -ForegroundColor Blue
    $r = GetResourceReader $global:ResourceFilePath
    try {
        $junkref = 0
        # some copied from GetNextScriptKey
        $r | Where-Object { [int]::TryParse($_.Key, [ref] $junkref) } | Select-Object @{Name='Key'; Expression={[System.Convert]::ToInt32($_.Key)}}, @{Name='Script'; Expression={$_.Value}} | Sort-Object -Property Key | ForEach-Object {
            $scriptContent = $_.Script -replace "'", "''" # escape ticks so the statement will complete
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
        Write-Host 'done' -ForegroundColor Blue
    }
    catch {
        Write-Host $_ -ForegroundColor Red
        exit
    }
    finally {
        $r.Close() > $null
    }
}

EnsureDatabaseProjectSelected
SetProjectBasedGlobals
# :Configure: Adjust as necessary.  Assumes all devs can share same local connection string.
$global:conStr = "Server=.\SQLEXPRESS;Database=$global:DatabaseProjectName;Trusted_Connection=Yes"
CreateTempTable
WriteResourcesToTable