param (
    [string] $OperationName, 
    [string] $TargetName, 
    [REF] $AllAnswer, 
    [string] $Warning = ""
    )

   if ($verbose) { $VerbosePreference = "continue" }

   # Check to see if "YES to All" or "NO to all" has previously been selected
   # Note that this technique requires the [REF] attribute on the variable.
   # Here is an example of how to use this:
      function Stop-Calc ([Switch]$Verbose, [Switch]$Confirm, [Switch]$Whatif)
      {
         $AllAnswer = $null
         foreach ($p in Get-Process calc)
         {   if (Should-Process Stop-Calc $p.Id ([REF]$AllAnswer) "`n***Are you crazy?" -Confirm:$Confirm -Whatif:$Whatif)
              {  Stop-Process $p.Id
              }
          }
        }
   if ($AllAnswer.Value -eq $false)
   {  return $false
   }elseif ($AllAnswer.Value -eq $true)
   {  return $true
   }



   if ($Whatif)
   {  Write-Host "What if: Performing operation `"$OperationName`" on Target `"$TargetName`""
      return $false
   }
   if ($Confirm)
   {
      $ConfirmText = @"
Confirm
Are you sure you want to perform this action?
Performing operation "$OperationName" on Target "$TargetName". $Warning
"@
      Write-Host $ConfirmText
      while ($True)
      {
         $answer = Read-Host @"
[Y] Yes  [A] Yes to All  [N] No  [L] No to all  [S] Suspend  [?] Help (default is "Y")
"@
         switch ($Answer)
         {
           "Y"   { return $true}
           ""    { return $true}
           "A"   { $AllAnswer.Value = $true; return $true }
           "N"   { return $false }
           "L"   { $AllAnswer.Value = $false; return $false }
           "S"   { $host.EnterNestedPrompt(); Write-Host $ConfirmText }
           "?"   { Write-Host @"
Y - Continue with only the next step of the operation.
A - Continue with all the steps of the operation.
N - Skip this operation and proceed with the next operation.
L - Skip this operation and all subsequent operations.
S - Pause the current pipeline and return to the command prompt. Type "exit" to resume the pipeline.
"@
                 }
         }
      }
   }

   Write-Verbose "Performing `"$OperationName`" on Target `"$TargetName`"."

   return $true
