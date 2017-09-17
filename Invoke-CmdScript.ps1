param([string] $script, [string] $parameters)
$tempFile = [IO.Path]::GetTempFileName()

cmd /c " `"$script`" $parameters && set > `"$tempFile`" "
if ($LASTEXITCODE -ne 0) {
    throw "Error executing CMD.EXE: $LASTEXITCODE"
}

Get-Content $tempFile | % {
    if($_ -match "^(.*?)=(.*)$") {
        Set-Content "env:\$($matches[1])" $matches[2]
    }
}

Remove-Item $tempFile
