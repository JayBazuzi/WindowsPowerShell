Set-StrictMode -Version Latest

function prompt {
    Set-StrictMode -Version Latest
    #
    # if the last command didn't give us a newline, take one.
    #
    if ($host.ui.RawUI.CursorPosition.X) {
        Write-Host
    }
    #
    # Figure out the history ID of the next command
    #
    $lastHistoryId = 0
    $lastHistoryItem = $null
    $delayMessage = ""
    if (Get-History) {
        $lastHistoryId = (Get-History | select -Last 1).id
        $lastHistoryItem = Get-History ($lastHistoryId)
    }
    #
    # If the last command took a long time, we want to report the delay
    #
    if($lastHistoryItem) {
        $duration = ($lastHistoryItem.EndExecutionTime - $lastHistoryItem.StartExecutionTime)
        ## Check if the last command took a long time
        if($duration.TotalSeconds -gt 30)
        {
            $delayMessage = " {0:00}h{1:00}m{2:00}s" -f $duration.TotalHours, $duration.Minutes, $duration.Seconds
        }
	else
        {
            $delayMessage = ""
        }
    }
    #
    # make a red line between commands, with the delay at the end.
    #

    Write-VcsStatus
    Write-Host -NoNewline " "
    Write-Host -NoNewline -ForegroundColor Red (Get-Location)
    Write-Host -NoNewline " "
    Write-Host -NoNewline -ForegroundColor Red (New-Object System.String @('-',($Host.UI.RawUI.WindowSize.Width - $host.ui.RawUI.CursorPosition.X - 1 - $delayMessage.Length))) 
    Write-Host -ForegroundColor Yellow "$delayMessage"

    Write-Host -NoNewLine -ForegroundColor White "#$($lastHistoryId + 1) ¯\_(°_°)_/¯ PS>"
    " "
}


Import-Module Posh-Git
# remove extra space at the start of the Git status
$GitPromptSettings.BeforeText = '['

function newguid {
	[guid]::NewGuid().Guid | Set-Clipboard
}