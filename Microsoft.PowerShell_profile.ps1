Update-Module -WhatIf

Import-Module PSReadLine
Import-Module posh-git

$global:GitPromptSettings.BeforeText = '['
$global:GitPromptSettings.AfterText  = '] '
$global:GitPromptSettings.DefaultPromptSuffix = '`n$(''>'' * ($nestedPromptLevel + 1)) '


function GetNextHistoryItemId {
    if (Get-History) {
        return (Get-History | select -Last 1).id + 1
    } else {
        return 1;
    }
}

function GetLastHistoryItemDuration {
    $lastHistoryItem = Get-History | select -Last 1
    if ($lastHistoryItem) {
        return ($lastHistoryItem.EndExecutionTime - $lastHistoryItem.StartExecutionTime)
    } else {
        return $null;
    }
}

function prompt {
    $origLastExitCode = $LASTEXITCODE
    
    # if the last command didn't give us a newline, take one.
    if ($host.ui.RawUI.CursorPosition.X) { Write-Host }

    # If the last command took a long time, we want to report the delay
    $lastHistoryItemDuration = GetLastHistoryItemDuration
    if($lastHistoryItemDuration -and $lastHistoryItemDuration.TotalSeconds -gt 1) {
        $delayMessage = " {0:00}:{1:00}:{2:00}" -f ($lastHistoryItemDuration.Hours, $lastHistoryItemDuration.Minutes, $lastHistoryItemDuration.Seconds)
    }

    Write-VcsStatus
    Write-Host -NoNewline " "
    Write-Host -NoNewline -ForegroundColor Red $(Get-Location)
    Write-Host -NoNewline " "
    $width = ($Host.UI.RawUI.WindowSize.Width - 2 - $host.ui.RawUI.CursorPosition.X) - $delayMessage.Length
    Write-Host -NoNewline -ForegroundColor Red (New-Object System.String @('-',$width))
    Write-Host -NoNewline -ForegroundColor Yellow $delayMessage

    Write-Host ""

    $global:LASTEXITCODE = $origLastExitCode
}

function .. { cd .. }

$env:path += ';' + (split-path $profile)

### tableau stuff

sal tube                tableau-tools/pipeline/tube.py
sal tcproof             tableau-tools/pipeline/tcproof.py
sal gsub                tableau-tools/pipeline/gsub.py
sal sourceSync          tableau-tools/SourceAnalyzers/sourceSync.py
sal format_opened       tableau-1.3/tools/clang_format_opened.py 
sal tableau             tableau-1.3/build/Release-x64/tableau.exe

function Exec-Block([string]$cmd) {
    Write-Host -ForegroundColor Yellow "$cmd"
    & ([scriptblock]::Create($cmd))

    # Need to check both of these cases for errors as they represent different items
    # - $?: did the powershell script block throw an error
    # - $lastexitcode: did a windows command executed by the script block end in error
    if ((-not $?) -or ($lastexitcode -ne 0)) {
        throw "Command failed to execute: $cmd"
    } 
}

function ttt($modules, $test, $config='Release')  {
    $modules | foreach {
        Exec-Block "tube --quiet --target test_$_"
    }

    if (!$?) {
        exit
    }

    $modules | foreach {
        Exec-Block ([scriptblock]::Create(" & tableau-1.3\build\$config-x64\test_$_.exe $test" ))
    }
}
