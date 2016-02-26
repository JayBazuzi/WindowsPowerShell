#####
# Get-GuiHelp.ps1
#####

param([string]$name = $( throw "must supply a name" ) )

if ($args) { throw "name only" }

if (test-path alias:$name) 
{
    $name = Get-Content alias:$name
}

$chmPath=(Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "powershell.chm")

if ($name.contains("about_"))
{
    $url = "mk:@MSITStore:" + $chmPath + "::/about/" + $name + ".help.htm"
}
elseif ($name.contains("-"))
{
    $url = "mk:@MSITStore:" + $chmPath + "::/cmdlets/" + $name + ".htm"
}

HH.EXE $url
