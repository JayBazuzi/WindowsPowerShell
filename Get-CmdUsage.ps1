param (
    [Management.Automation.CommandInfo] $cmd,
    [Switch] $help
)

if ($help)
{
	throw $(Get-CmdUsage.ps1 $MyInvocation.MyCommand)
}

if (!$cmd)
{
	throw 'must supply a CommandInfo, e.g. "Get-CmdUsage $MyInvocation.MyCommand"'
}

if ($args)
{
	throw "unrecognized args: $args"
}

if ($cmd -is [Management.Automation.ExternalScriptInfo])
{
    $txt = cat $cmd.Definition
}
else
{
    $txt = $cmd.Definition.split("`n")
}

$display = 0
# return the formatted option text
[string]::Join("`n", 
    $(switch -regex ($txt)
        {
           '^ *param *\('      { $display++; continue }
           '^ *\) *$'          { $display++; continue }
           {$display -eq 1}    {$_; continue}
        }
    )
)

