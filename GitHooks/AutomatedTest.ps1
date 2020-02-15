function GetResourceReader([string] $path) {
    New-Object System.Resources.ResourceReader -ArgumentList $path
}

function GetResourceWriter([string] $path) {
    New-Object System.Resources.ResourceWriter -ArgumentList $path
}

# iterate files in $inputPath, write them all into resource file at $outputPath using file names as keys
# Theh output file can't be in the same dir as input
function WriteFilesToResource($inputPath, $outputPath) {
    $writer = GetResourceWriter $outputPath

    try {
        Get-ChildItem $inputPath -File | Where-Object {$null -ne $_} | ForEach-Object {
            $content = Get-Content $_
            $writer.AddResource($_.Name, $content)
        }
    }
    finally {
        $writer.Close() > $null
    }
    
}    

function ViewResources($path) {
    $reader = GetResourceReader $path
    try {
        $reader | ForEach-Object {
            Write-Host "$($_.Key)--> $($_.Value)"
        }
    }
    finally {
        $reader.Close() > $null
    }
}

function SetLocationToRepoRoot {
    Set-Location (($PSCommandPath | Split-Path) | Split-Path)
}

$tempFileDir = 'C:\temp\DatabaseMigration\ResourceInputFiles'
SetLocationToRepoRoot
$resourceFilePath = 'C:\source\database-migration\DatabaseMigrator\DatabaseMigrationScripts.resources'

Write-Host "$([System.Environment]::NewLine)Setting content for master.$([System.Environment]::NewLine)"
Set-Location $tempFileDir
Get-ChildItem | Remove-Item #flushit
SetLocationToRepoRoot
Set-Content -Path "$tempFileDir\1" -Value 'create table'
Set-Content -Path "$tempFileDir\2" -Value 'first'

Write-Host "$([System.Environment]::NewLine)Committing to master.$([System.Environment]::NewLine)"
git checkout master
WriteFilesToResource $tempFileDir $resourceFilePath
git commit -a -m 'reset master'

Write-Host "$([System.Environment]::NewLine)Switch to other, add a third resource$([System.Environment]::NewLine)"
git checkout -b other
Set-Content -Path "$tempFileDir\3" -Value 'second from other'
WriteFilesToResource $tempFileDir $resourceFilePath
git commit -a -m 'added 3 to other'

Write-Host "$([System.Environment]::NewLine)Back to master, branch to current, add different third resource.$([System.Environment]::NewLine)"
git checkout master
git checkout -b current
Set-Content -Path "$tempFileDir\3" -Value 'second from current'
WriteFilesToResource $tempFileDir $resourceFilePath
git commit -a -m 'added 3 to current'

Write-Host "$([System.Environment]::NewLine)Back to master, merge in other; no conflict.$([System.Environment]::NewLine)"
git checkout master
git merge other

Write-Host "$([System.Environment]::NewLine)Back to current, merge in master; merge driver invoked.$([System.Environment]::NewLine)"
git checkout current
git merge master

Write-Host "$([System.Environment]::NewLine)Scripts should be 1)'create table', 2)'first', 3)'second from Other', 4)'second from current'"
ViewResources $resourceFilePath

Write-Host "$([System.Environment]::NewLine)"
git checkout master
git branch -D current
git branch -D other