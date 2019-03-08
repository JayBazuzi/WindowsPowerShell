Import-Module PSReadLine
Import-Module posh-git

Set-PSReadlineOption -BellStyle None

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

### disable backspace beep
Set-PSReadlineOption -BellStyle None

