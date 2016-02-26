param (
	[switch]$IEC, 	# see http://en.wikipedia.org/wiki/Binary_prefix
	[switch]$verbose
)

begin
{ 
	if ($verbose) { $VerbosePreference = "continue" }
	if ($args) { 
		throw "Usage:`n$(Get-CmdUsage $MyInvocation.MyCommand)"
	}
	$prefixes = @('', 'K', 'M', 'G', 'T', 'P', 'E', 'Z', 'Y')
	$base = 1024;
}


process 
{
	if($_ -eq $null)
	{
		$null
		return
	}

	$magnitude = [Math]::Floor([Math]::Log($_, 1024))

	Write-Verbose "`$magnitude = $magnitude"

	if($magnitude -eq 0)
	{
		[string]$mantissa = $_
		[string]$label = 'B';
	}
	else
	{
		[string]$mantissa = [String]::Format("{0:N}", $_ / [Math]::Pow(1024, $magnitude))

		Write-Verbose "`$mantissa = $mantissa"

		[string]$label = $prefixes[$magnitude]

		if ($IEC)
		{
			$label += "i"
		}

		$label += "B"
	}


	[String]::Format("{0} {1}", $mantissa, $label)
}

end
{
}