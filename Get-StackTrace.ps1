trap { continue }

2..100 | foreach {

	$inv = Get-Variable -Scope $_ MyInvocation 2>$null

	$positionMessage = $inv.Value.PositionMessage

	if ($inv) { 
		Write-Host -Foreground "Cyan" $positionMessage.replace("`n","") 
	}
}
exit
