$env:TABNINJA_CACHED_BUILD="OFF"

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

sal tube                        tableau-tools/pipeline/tube.py
sal sourceSync                  tableau-tools/SourceAnalyzers/sourceSync.py
sal format_opened               tableau-1.3/tools/clang_format_opened.py
sal tablint                     tableau-1.3/tools/tablint.py

sal sparse_branch_create        tableau-1.3/tools/sparse_branch_create.py
sal sparse_branch_pull_request  tableau-1.3/tools/sparse_branch_pull_request.cmd
sal sparse_branch_merge_down    tableau-1.3/tools/sparse_branch_merge_down.cmd

sal rtr                         tableau-1.3/build/Release-x64/tableau.exe
sal rtd                         tableau-1.3/build/Debug-x64/tableau.exe


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
        Exec-Block "tube --target test_$_ --config $config"
    }

    if (!$?) {
        exit
    }

    $modules | foreach {
        Exec-Block ([scriptblock]::Create(" & tableau-1.3\build\$config-x64\test_$_.exe $test" ))
    }
}
