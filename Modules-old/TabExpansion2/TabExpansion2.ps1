
function TabExpansion2
{
    [CmdletBinding()]
    param([string]$line, [int]$cursor)
    
    $TabModule = (Get-Module TabExpansion2)
    
    # Use a wildcard to avoid adding an error to $error.
    if ($null -eq (& $TabModule Get-Variable GetCommandProxy*))
    {
        function MakeProxy
        {
            param($cmd)
            
            $md = New-Object System.Management.Automation.CommandMetadata (Get-Command -Type Cmdlet $cmd)
            $script = [System.Management.Automation.ProxyCommand]::Create($md)
            $script = $script.Replace('$myInvocation.CommandOrigin','')
            [ScriptBlock]::Create($script).GetNewClosure()
        }
    
        & $TabModule Set-Variable -Name GetCommandProxy -Value (MakeProxy Get-Command)
        & $TabModule Set-Variable -Name GetVariableProxy -Value (MakeProxy Get-Variable)
        & $TabModule Set-Variable -Name GetChildItemProxy -Value (MakeProxy Get-ChildItem)
    }
    
    & $TabModule TabExpansion2 @PSBoundParameters
}

$global:oldTabExpansion = $function:tabExpansion

function TabExpansion
{
    [CmdletBinding()]
    param($line, $lastword)
    
    $null = $PSBoundParameters.Remove('lastword')
    $result = TabExpansion2 @PSBoundParameters -cursor ($line.Length)
    
    $lastWordOffset = $line.Length - $lastword.Length
    $prefix = $line.Substring($lastWordOffset, $result.FirstReplacementOffset - $lastWordOffset)
    
    foreach ($str in $result)
    {
        # TabExpansion2 ignores lastword, but returns back the line positions of text to replace.
        # TabExpansion replaces lastword.  We must tweak the results to include parts of lastword
        # that TabExpansion2 doesn't think needs replacing.
        Write-Output ("{0}{1}" -f $prefix,$str)
    }
}