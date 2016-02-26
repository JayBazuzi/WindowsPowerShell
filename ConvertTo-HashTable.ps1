# ConvertTo-HashTable.ps1 
#   From http://blogs.msdn.com/powershell/archive/2008/11/23/convertto-hashtable-ps1-part-2.aspx

param( 
    [string]  
    $key, 
    $value 
) 
Begin 
{ 
    $hashTables  = @()
    foreach ($v in @($value))
    {
      $hashTables += @{} 
    }
    $Script = $false 
    if ($value -is [ScriptBlock]) 
    { 
        $Script = $true 
    } 
} 
Process 
{ 
    $thisKey = $_.$Key 
    for ($i = 0 ; $i -le $hashTables.Count; $i++)
    {
        $hash = $hashTables[$i]
        if (@($Value)[$i] -is [ScriptBlock])
        {
            $hash.$thisKey = & @($Value)[$i]
        }
        else
        {
            $hash.$thisKey = $_.$(@($Value)[$i]) 
        }
    }
} 
End 
{ 
    foreach ($hash in $hashtables)
    {
        Write-Output $hash 
    }
}