Set-StrictMode -Version latest

$env:path += ";" + (Split-Path $PROFILE)

function gcir { gci -Recurse . @args }
function gcid { gci @args | where { $_.PSIsContainer } }
function .. { Set-Location .. }

Set-Alias n notepad.exe
Set-Alias ql Quote-List
Set-Alias qs Quote-String
Set-Alias ss Select-String
Set-Alias on Out-Null
Set-Alias ?? Compare-Property

function tfu {
    tf undo $/ /r /noprompt 
}
