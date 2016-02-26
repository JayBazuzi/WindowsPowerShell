<#

Command expansion

  If a command is expected (beginning of the command line or just after a '|', the pattern
  is assumed to be a command name.  PowerShell commands (cmdlets, functions, aliases) are
  expanded, as well as files with an extension in $env:PATHEXT.

Argument expansion

  For built-in cmdlets and PowerShell scripts and functions, tab expansion attempts
  to figure out which parameter is being completed.  If that succeeds and the parameter
  type is an enum, then member of the enum are used for expansion.  Otherwise, tab
  expansion looks for a custom handler for the command/parameter pair or just the parameter
  name.  These can be customized in your profile.
  
  Examples:
  
      Set-ExecutionPolicy <TAB>
                           => Set-ExecutionPolicy -ExecutionPolicy Unrestricted
      Set-ExecutionPolicy -ExecutionPolicy Unrestricted <TAB>
                           => Set-ExecutionPolicy -ExecutionPolicy Unrestricted -Scope Process
      new-object arraylist<TAB>
                           => new-object System.Collections.ArrayList
      new-object -ComObject Word<TAB>
                           => new-object -ComObject Word.Application.12
      ipmo <TAB>           => ipmo <modules in $env:PSModulePath, or files matching *.psd1,*.psm1>
      cd <TAB>             => cd <directories only>
      rmo <TAB>            => rmo <loaded modules only>
      kill -name p<TAB>    => kill -name <processes starting with p>
      get-eventlog <TAB>   => get-eventlog <event log names>
      get-winevent <TAB>   => get-winevent <windows event log names>
      gwmi win32_pro<TAB>  => gwmi Win32_Process

Parameter expansion

  Parameters for built-in cmdlets, PowerShell scripts and functions are expanded when
  tab expansion sees parameter (starting with '-'.).  Note that parameter aliases are
  supported.
  
  Examples:
  
      dir -r<TAB>       => dir -Recurse
      gcm -t<TAB>       => gcm -Type
      gcm -c<TAB>       => gcm -CommandType

Type expansion

  Type literals starting with '[foo' will expand to the complete type name for
  any namespace, type, or type accelerator matching 'foo*'.  Wildcards are allowed.

  Examples:
  
    [arraylist<TAB>     => [System.Collections.ArrayList]
    [dictionary<TAB>    => [System.Collections.Generic.Dictionary[
    [System.Collections.Generic.Dictionary[str<TAB>
                        => [System.Collections.Generic.Dictionary[string]]
    [System.Collections.Generic.Dictionary[string,pow<TAB>
                        => [System.Collections.Generic.Dictionary[string,powershell]]
    [*app<TAB>          => [System._AppDomain]
    [sys<TAB>           => [System.
    [pro<TAB>           => [System.Diagnostics.Process]

Member expansion

  Members can be completed when the type of the initial expression can be determined.
  
  Examples:
  
      $profile.A<TAB>       => $profile.AllUsersAllHosts
      [AppDomain]::Cur<TAB> => [AppDomain]::CurrentDomain
      

Comment expansion

  Comments of the form '#nnn' will expand to the history item # nnn
  Comments of the form '#foo' will expand to all items in the history matching foo

File expansion

  File shares are expanded
  
  Examples:
  
      dir \\machine\s<TAB> => dir \\machine\share
#>

param($forBackgroundInitialization = $false)

Set-StrictMode -v 2

$PSTokenType = [System.Management.Automation.PSTokenType]

############################################################################
## Find the matching token (parents, braces, etc.)
############################################################################
function FindGroupMatch
{
    param($tokens, $i)

    $startToken = $tokens[$i]
    switch ($startToken.Type)
    {
        <#case#> $PSTokenType::GroupEnd
        {
            # Group End can be:
            #    Close paren: )
            #    Close brace: }
            $direction = -1
            $matchType = $PSTokenType::GroupStart
            $matchChar = if ($startToken.Content -eq ")") { "(" } else { "{" }
            $stopAt = 0
            break
        }
        
        <#case#> $PSTokenType::GroupStart
        {
            # Group Start can be:
            #    Array subexpression: @(
            #    Subexpression: $(
            #    Hash literal: @{
            #    Open paren: (
            #    Open brace: {
            $direction = 1
            $matchType = $PSTokenType::GroupEnd
            $matchChar = if ($startToken.Content[-1] -eq "(") { ")" } else { "}" }
            $stopAt = $tokens.Count
            break
        }
        
        <#case#> $PSTokenType::Operator
        {
            if ($startToken.Content -eq "[")
            {
                $direction = 1
                $matchType = $PSTokenType::Operator
                $matchChar = "]"
                $stopAt = $tokens.Count
            }
            elseif ($startToken.Content -eq "]")
            {
                $direction = -1
                $matchType = $PSTokenType::Operator
                $matchChar = "["
                $stopAt = 0
            }
            else
            {
                return -1
            }
        }
        
        default { return -1 }
    }
    
    $nesting = 0
    do
    {
        $i += $direction
        if ($tokens[$i].Type -eq $matchType -and $tokens[$i].Content[-1] -eq $matchChar)
        {
            if ($nesting -eq 0)
            {
                return $i
            }
            else
            {
                --$nesting
            }
        }
        elseif ($tokens[$i].Type -eq $startToken.Type -and $tokens[$i].Content[-1] -eq $startToken.Content[-1])
        {
            ++$nesting
        }
    } while ($i -ne $stopAt)
    
    return -1
}


############################################################################
## Scanning backwards, find the command the current token belongs to
############################################################################
function FindCommandAndParameters
{
    param($cursorTokenIndex, $tokens)
    
    # Scan backwards to find the command
    $i = $cursorTokenIndex - 1
    $command = ''
    :scan while ($i -ge 0 )
    {
        switch ($tokens[$i].Type)
        {
            <#case#> $PSTokenType::Command
            {
                $command = $tokens[$i].Content
                break scan
            }
            
            <#case#> $PSTokenType::GroupEnd
            {
                $m = FindGroupMatch $tokens $i
                if ($m -ne -1) { $i = $m }
            }
            
            <#case#> $PSTokenType::Operator
            {
                if ($tokens[$i].Content -eq '|')
                {
                    break scan
                }
            }
        }
    
        --$i
    }
    
    if ($command -eq '')
    {
        # Scanning backwards did not find a Command token
        # We're either just before the start, or at a '|',
        # So look at the next token, it should be a '&' or '.'
        ++$i
        if ($tokens[$i].Type -eq $PSTokenType::Operator)
        {
            if ($tokens[$i].Content -eq '&' -or
                $tokens[$i].Content -eq '.')
            {
                ++$i
                switch ($tokens[$i].Type)
                {
                    <#case#> $PSTokenType::String
                    {
                        $command = $tokens[$i].Content
                        break
                    }
                    
                    <#case#> $PSTokenType::Variable
                    {
                        $command = (& $GetVariableProxy -Name ($tokens[$i].Content)).Value
                        break
                    }
                }
            }
        }
    }
    
    $parameters = $null
    try
    {
        $cleanup = $false
        if ($command -is [scriptblock])
        {
            set-item function:global:tabExpansionHackHackHack $command
            $command = 'tabExpansionHackHackHack'
            $cleanup = $true
        }
    
        # TODO - add arguments to get any dynamic parameters
        # TODO - add some sort of support for native command parameters
        if (!($command -is [System.Management.Automation.CommandInfo]))
        {
            $command = @(& $GetCommandProxy -ErrorAction SilentlyContinue $command)[0]
        }
        if ($null -ne $command)
        {
            if ($command -is [System.Management.Automation.AliasInfo])
            {
                $command = $command.ResolvedCommand
            }
        
            $parameters = $command.Parameters
        }
    }
    finally
    {
        if ($cleanup)
        {
            Remove-Item function:global:tabExpansionHackHackHack
        }
    }
    
    # Return 2 values - the command, and the token index for the command
    $command
    $i
    $parameters
}

############################################################################
## Scanning backwards, find the command the current token belongs to
############################################################################
function DetermineDollarUnderType
{
    param($tokens, $dollarUnderIndex)
    
    # First, we assume $_ is used in the following pattern:
    #    something | maybe other stuff | otherthing random stuff { $_.
    # We first scan back to the opening curly, then back to the pipe, then back
    # one more step.
    
    function ScanBackFor
    {
        param($predicate)
        
        for (; $idx -ge 0; --$idx)
        {
            if ($tokens[$idx].Type -eq $PSTokenType::GroupEnd)
            {
                $idx = FindGroupMatch $tokens $idx
            }
            elseif (& $predicate)
            {
                break
            }
        }
    }

    $idx = $dollarUnderIndex
    . ScanBackFor { $tokens[$idx].Type -eq $PSTokenType::GroupStart -and $tokens[$idx].Content -eq '{' }
    if ($idx -eq -1) { return }  
    . ScanBackFor { $tokens[$idx].Type -eq $PSTokenType::Operator -and $tokens[$idx].Content -eq '|' }
    if ($idx -eq -1) { return }  
    $savePipeIdx = $idx
    . ScanBackFor { $tokens[$idx].Type -eq $PSTokenTYpe::Command }
    if ($idx -ne -1)
    {
        # We found the command.  Figure out it's output type
        & $GetCommandProxy -Name $tokens[$idx].Content |
            ForEach-Object {
                if ($_ -is [System.Management.Automation.AliasInfo])
                {
                    $_ = $_.ResolvedCommand
                }
                $_.OutputType | ForEach-Object {
                    if ($null -ne $_.Type)
                    {
                        Write-Output $_.Type
                    }
                }
            }
    }
    else
    {
        # Hmm, 
    }
}

############################################################################
## All results returned for tabExpansion2 need to go through here.  This gives a
## single place to make changes if we need (like adding properties to the result
## and ensuring uniqueness.)
############################################################################
function AppendResult
{
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline=$true, Mandatory=$true)]
          [ValidateNotNullOrEmpty()]
          [string]
          $obj)
    process
    {
        if ($results.IndexOf($obj) -eq -1)
        {
            $results.Add($obj) 
            
            if ($results.Count -ge 50)
            {
                # Non-local goto when we have more than enough results
                # This keeps tab expansion fast, and some hosts seem to
                # have problems when too many results are returned.
                
                break plentyOfResults
            }
        }
    }
}

############################################################################
## Add quotes to the command argument (if necessary), then append
############################################################################
function QuoteArgumentIfNecessary
{
    [CmdletBinding()]
    param([Parameter(ValueFromPipeline=$true, Mandatory=$true)]
          [ValidateNotNullOrEmpty()]
          [string]
          $obj)
    process
    {
        if ($obj -match '\s')
        {
            $obj = "'$obj'"
        }
        Write-Output $obj
    }
}

############################################################################
## Complete the name of a command
############################################################################
function ExpandCommand
{
    param([string]$commandName, $getCommandParameters = @{})
    
    function MakeCommandsUnique
    {
        param([System.Management.Automation.CommandInfo[]]$Commands, [switch]$AddModulePrefix)
        
        $commandTable = @{}
        $notUnique = @{}
        foreach ($command in $commands)
        {
            if ($AddModulePrefix -and $command.ModuleName -ne '')
            {
                $name = "{0}\{1}" -f $command.ModuleName,$command.Name
            }
            else
            {
                $name = $command.Name
            }
            
            if ($commandTable[$name] -eq $null)
            {
                $commandTable[$name] = @($command)
            }
            else
            {
                $notUnique[$name] = $true
                $commandTable[$name] += $command
            }
        }
        
        
        if (!$AddModulePrefix)
        {
            # Add module prefixes for commands that are not unique
            foreach ($notUniqueName in $notUnique.Keys)
            {
                $notUniqueCommands = $commandTable[$notUniqueName]
                
                # Remove the name, it may be replace below, but we'll use module qualified names
                # assuming all ambiguous commands come from modules
                $commandTable.Remove($notUniqueName)
                
                foreach ($command in $notUniqueCommands)
                {
                    if ($command.ModuleName -ne '')
                    {
                        $name = "{0}\{1}" -f $command.ModuleName,$command.Name
                    }
                    else
                    {
                        $name = $command.Name
                    }
                    $commandTable[$name]++
                }
            }
        }
        
        $commandTable.Keys | sort-object
    }
    
    $commandName += '*'
    if ($commandName.IndexOfAny('/\:') -eq -1)
    {
        $commands = @(
            # Find all commands not in modules.
            & $GetCommandProxy -Name $commandName @getCommandParameters | Where-Object { $_.Module -eq $null }
            
            # Add all commands in modules - this is how we discover commands that
            # should be considered ambiguous
            Get-Module | ForEach-Object { & $_ $GetCommandProxy -Module $_.Name -Name $commandName @getCommandParameters }
        )
        #$commands | ft Name,Definition,Module,ModuleName | out-host
        MakeCommandsUnique $commands | AppendResult
    }
    else
    {
        # Get-Command doesn't support module qualified commands or relative/rooted file paths
        if ($commandName -match '^([^\\]+)\\([^\\]+)$')
        {
            MakeCommandsUnique -AddModulePrefix (& $GetCommandProxy -Name $matches[2] -Module $matches[1] @getCommandParameters) | AppendResult
        }
        
        if (Test-Path $commandName)
        {
            $executableExtensions = $env:pathext -split ';'
            $executableExtensions += '.ps1'
            
            Resolve-Path -ea SilentlyContinue -Relative $commandName |
                Where-Object { ($executableExtensions -contains [System.IO.Path]::GetExtension($_.Path))  } |
                    AppendResult
        }
    }    
}

############################################################################
## Complete a filename
############################################################################
function ExpandFileName
{
    param($filename, [scriptblock]$filter = { $true })
        
    try
    {
        if ($filename -match '^\\\\([^\\]+)\\([^\\]*)$')
        {
            # Complete a network share - yes, we are ignoring the filter here,
            # not sure if that's a good idea or not.  Maybe add a filter for shares?
            $server = $matches[1]
            $share = $matches[2] + '*'
            [TabExpansion2.NativeMethods]::GetFileShares($server) |
                Where-Object { $_[-1] -ne '$' -and $_ -like $share} |
                    ForEach-Object { AppendResult ("\\{0}\{1}" -f $server,$_) }
        }
        else
        {
            # TODO: Performance of -relative is pretty bad when there are lots of files (~3000 in this case):
            #
            # PS> (measure-command { resolve-path $env:WINDIR\System32\* }).TotalSeconds
            # 0.6579249
            # PS> (measure-command { resolve-path -relative $env:WINDIR\System32\* }).TotalSeconds
            # 3.0775328

            $relative = !(('~','\','/' -contains $filename[0]) -or (split-path -Path $filename -IsAbsolute))
                
            $files = Resolve-Path -Relative:$relative "$filename*" -ErrorAction SilentlyContinue |
                Where-Object $filter
            $files = foreach ($file in $files)
            {
                $path = if ($file -is [System.Management.Automation.PathInfo]) { $file.Path } else { $file }
                if ($path -match "(.*)::(.*)" -and $matches[1] -eq $pwd.Provider)
                {
                    $path = $matches[2]
                }
                Write-Output $path
            }
            $files | Sort-Object -Property @{Expression= {$_ -notlike $filename}},
                                           @{Expression= {$_}} |
                QuoteArgumentIfNecessary | AppendResult
        }
    }
    catch
    {
        Write-Verbose ($_ | out-string)
    }
}

############################################################################
## Complete a parameter to a command
############################################################################
function ExpandCommandParameter
{
    param([string]$parameter)
    
    $null,$null,$parameters = FindCommandAndParameters $cursorTokenIndex $tokens
    if ($null -ne $parameters)
    {
        $pattern = $parameter.SubString(1) + '*'
    
        # expand the parameter sets and emit the matching elements        
        foreach ($p in $parameters.Values)
        {
            # Only look at aliases when a pattern is specified, otherwise it's confusing
            # to see both the alias and the actual parameter.
            if ($pattern.Length -gt 1)
            {
                foreach ($a in $p.Aliases)
                {
                    # Short aliases are skipped, in part to avoid picking up
                    # the *Variable parameter aliases, but also because people
                    # don't hit tab for short parameters.
                    if ($a.Length -gt 2 -and $a -like $pattern) { AppendResult ('-' + $a) }
                }
            }
            
            if ($p.Name -like $pattern) { AppendResult ('-' + $p.Name) }
        }
    }
}

############################################################################
## Complete an enumerator for a known enum type
############################################################################
function ExpandEnumArgument
{
    param([type]$type, [string]$argument, [string]$prefix)
    
    # TODO: support the 'a,b,c' (quoted) form of an enumerator
    [Enum]::GetNames($type) |
        Where-Object { $_ -like "$argument*" } |
            ForEach-Object { "$prefix$_" } | AppendResult
}    

############################################################################
## Complete an argument to a command
############################################################################
function ExpandCommandArgument
{
    param([string]$argument)
    
    # The tokenizer assumes anything starting w/ a '-' is a parameter.  This
    # isn't always true, e.g. a lone '-' or '-1' will be tokenized as an argument.
    if ($argument.StartsWith('-'))
    {
        ExpandCommandParameter $argument
        
        # If we did find a parameter, then skip expanding as an argument
        # If we didn't find any parameters, then try expanding as an argument
        if ($results.Count -gt 0)
        {
            return
        }
    }
    
    $command,$commandTokenIndex,$parameters = FindCommandAndParameters $cursorTokenIndex $tokens
    if ($command -is [System.Management.Automation.ApplicationInfo])
    {
        ExpandNativeCommandArgument $command $argument
    }
    elseif ($parameters -ne $null)
    {
        function GetParameterFromPartialName 
        {
            param($parameterToken)

            $parameterName = $parameterToken.Content.SubString(1)
            $parameter = $parameters[$parameterName]
            if ($parameter -eq $null)
            {
                # The parameter may have been abbreviated or an alias was used.  Look for those
                $parameter = $parameters.Values | Where-Object {
                    $_.Name -like "$parameterName*" -or @($_.Aliases | Where-Object { $_ -like "$parameterName*" } ).Length}
            }
            $parameter
        }
        
        function ScanBackwordsForParameter
        {
            $prevArgInCurrentArg = $false
            :scan for ($i = $cursorTokenIndex - 1; $i -gt $commandTokenIndex; --$i)
            {
                switch ($tokens[$i].Type)
                {
                    <#case#> $PSTokenType::CommandParameter
                    {
                        return $tokens[$i]
                    }
                    
                    <#case#> $PSTokenType::CommandArgument
                    {
                        # We found another argument.  We can't have
                        # 2 CommandArgument tokens for 1 parameter, so
                        # we shouldn't keep looking for a CommandParameter.
                        if ($i + 1 -eq $tokens.Count)
                        {
                            break scan
                        }
                        if (($tokens[$i + 1].Type -ne $PSTokenType::Operator) -or
                            ($tokens[$i + 1].Content -ne ','))
                        {
                            break scan
                        }
                    }
                    
                    <#case#> $PSTokenType::GroupEnd
                    {
                        $m = & (GetTabHelper FindGroupMatch) $tokens $i
                        if ($m -ne -1) { $i = $m }
                        break
                    }
                }
            }
        }
        
        # Figure out what argument we're trying to complete
        # It may be positional, or named.  Check named first.
        $parameter = $null
        $parameterToken = ScanBackwordsForParameter
        if ($null -ne $parameterToken)
        {
            $parameter = GetParameterFromPartialName $parameterToken
            if (($parameter -is [System.Management.Automation.ParameterMetadata]) -and ($parameter.ParameterType -eq [switch]))
            {
                $parameter = $null
            }            
        }

        # It looks as though the argument is not named (either because we couldn't find
        # a parameter before the argument, it was ambiguous, or it was a switch parameter
        # So assume it is a positional argument, and try figure out which parameter it is.
        # NOTE: This code does a poor job dealing with multiple parameter sets
        $namedPositionals = @{}
        if ($parameter -eq $null)
        {
            $isNamed = $false
            $positionalArgument = 0
            $isNamedArgument = $false
            
            for ($i = $commandTokenIndex + 1; $i -lt $cursorTokenIndex; ++$i)
            {
                if ($tokens[$i].Type -eq $PSTokenType::CommandParameter)
                {
                    # Attempt to figure out if the parameter accepts an argument.  If we can't
                    # figure it out, assume it does
                    $isNamedArgument = $true
                    
                    $parameter = GetParameterFromPartialName $tokens[$i]
                    if ($parameter -is [System.Management.Automation.ParameterMetadata])
                    {
                        if ($parameter.ParameterType -eq [switch])
                        {
                            $isNamedArgument = $false
                        }
                        else
                        {
                            # Check to see if this parameter is positional, and remember it if so
                            $position = @($parameter.ParameterSets.Values | Where-Object { $_.Position -ge 0 })
                            if ($position.Length)
                            {
                                ++$namedPositionals[$position[0].Position]
                            }
                        }
                        
                        # If this 
                    }
                    
                    continue
                }
                
                if (!$isNamedArgument)
                {
                    ++$positionalArgument
                    
                    # TODO: skip over groups
                }
            }
            
            # Now try to figure the correct parameter.  We haven't attempted to figure out
            # the parameter set, so we'll collect all parameters at any given position and
            # assume it could be any of them.
            $positionalParameters = @(1..$parameters.Keys.Count | ForEach-Object {
                new-object System.Collections.ArrayList
            })

            $parameters.Values | ForEach-Object {
                $currentParameter = $_
                $_.ParameterSets.Values | ForEach-Object { $_.Position } |
                    Sort-Object -Unique | Where-Object { $_ -ge 0 } |
                        ForEach-Object {
                            $null = $positionalParameters[$_].Add($currentParameter)
                        }
            }
            
            # Figure out which position the argument is in, skipping positional arguments that were named
            for ($i = 0; $i -lt $positionalParameters.Count; ++$i)
            {
                if ($namedPositionals[$i] -gt 0)
                {
                    ++$positionalArgument
                }
            }
            
            $parameter = $positionalParameters[$positionalArgument]
        }
        else
        {
            $isNamed = $true
        }
        
        $parameter | ForEach-Object {
            if ($_ -is [System.Management.Automation.ParameterMetadata])
            {
                $parameterType = $_.ParameterType
                if ($null -ne $parameterType)
                {
                    if ($parameterType.IsEnum)
                    {
                        if ($isNamed)
                        {
                            ExpandEnumArgument $parameterType $argument
                        }
                        else
                        {
                            ExpandEnumArgument $parameterType $argument -prefix "-$($_.Name) "
                        }
                    }
                }
                
                foreach ($attribute in $_.Attributes)
                {
                    if ($attribute -is [System.Management.Automation.ValidateSetAttribute])
                    {
                        $attribute.ValidValues |
                            Where-Object {
                                $_ -like "$argument*" } | AppendResult
                    }
                }
                
                $argCompleter = $argumentCompleter["${command}:$($_.Name)"]
                if ($argCompleter -eq $null)
                {
                    $argCompleter = $argumentCompleter[$_.Name]
                }
                if ($null -ne $argCompleter)
                {
                    & $argCompleter $argument $isNamed | AppendResult
                }
            }
        }            
    }
    
    if ($results.Count -eq 0)
    {
        ExpandFileName $argument
    }
}

############################################################################
## Expand arguments/parameters for a native command
############################################################################
function ExpandNativeCommandArgument
{
    param($command, $argument)
    
    $sb = $nativeCommandArgumentCompleters[$command.Name]
    if ($null -ne $sb)
    {
        & $sb $argument | AppendResult
    } 
}

$varsRequiringQuotes = ('-`&@''#{}()$,;|<> .\/' + "`t").ToCharArray()
$varScopes = 'global','local','script','private'

############################################################################
## Complete a variable name
############################################################################
function ExpandVariable
{
    param([string]$var)

    $colon = $var.IndexOf(':')    
    if ($colon -eq -1)
    {
        $pattern = 'variable:{0}*' -f $var
        $provider = ''
    }
    else
    {
        $provider = $var.SubString(0, $colon)
        if ($varScopes -contains $provider)
        {
            # Remove the scope for Get-ChildItem (
            $pattern = 'variable:{0}*' -f ($var.SubString($colon+1))
        }
        else
        {
            $pattern = $var + '*'
        }
        $provider += ':'
    }
    
    & $GetChildItemProxy $pattern |
        Sort-Object Name |
            ForEach-Object {
                if ($_.Name.IndexOfAny($varsRequiringQuotes) -eq -1)
                {
                    '${0}{1}' -f $provider,$_.Name
                }
                else
                {
                    '${{{0}{1}}}' -f $provider,$_.Name
                }
            } | AppendResult
    
    # Drive names are also useful for completion of variables.
    # REVIEW: maybe skip file system drives, they aren't commonly used w/ variable syntax
    Get-PSDrive -Name "$var*" | Sort-Object Name | ForEach-Object { '$' + $_.Name + ':' } | AppendResult
}

############################################################################
## Complete a type
############################################################################
function ExpandType 
{
    param([string]$type)
    
    $TypeCache = GetTypeCache
    
    if ($null -ne $TypeCache)
    {
        function add-delimiters
        {
            [CmdletBinding()]
            param([Parameter(ValueFromPipeline=$true,Mandatory=$true)]$type)
            
            process {
                $suffix = if ($type[-1] -ne '.' -and $type[-1] -ne '[') { ']' * ($prefix.GetEnumerator() -eq '[').Count } else { '' }
                "{0}{1}{2}" -f $prefix, $type, $suffix
            }
        }
        
        # Figure out if we are expanding a generic type argument, or the whole type.
        
        $matchStr,$prefix = if ($type[0] -eq '[') { $type.Substring(1), '[' } else { $type, '' }     
        
        $index = $matchStr.LastIndexOfAny('[,')
        if ($index -ge 0)
        {
            $prefix = $type.SubString(0, $index + 2)
            $matchStr = $matchStr.SubString($index + 1)
        }
        
        Search-DataTable $TypeCache.accelerators Accelerator "$matchStr*" { $_.Accelerator } | add-delimiters | AppendResult
        Search-DataTable $TypeCache.namespaces Namespace "$matchStr*" { $_.namespace } | add-delimiters | AppendResult
        Search-DataTable $TypeCache.fulltypes FullType "$matchStr*" { $_.fulltype } | add-delimiters | AppendResult
        Search-DataTable $TypeCache.typehash Type "$matchStr*" { $_.fulltype } | add-delimiters | AppendResult
    }
}

############################################################################
## Complete a member (property, method, etc.)
############################################################################
function ExpandMember 
{
    param($memberName)
    
    function MemberAccessTokenKind
    {
        param($token)
        
        $result = ''
        if ($token.Type -eq $PSTokenType::Operator)
        {        
            if ($token.Content -eq '.')
            {
                $result = 'instance'
            }
            elseif ($token.Content -eq '::')
            {
                $result = 'static'
            }
        }
        $result
    }

    # We want to start with the operator, so skip over any partial member name
    $idx = $cursorTokenIndex
    if ($tokens[$idx].Type -eq $PSTokenType::Member)
    {
        --$idx
    }

    function IsRootToken
    {
        return ($idx -eq 0) -or ((MemberAccessTokenKind $tokens[$idx-1]) -eq '')
    }
    
    # Before resolving anything, we scan backwards through the expression.  As we
    # scan, we remember the members, the relevant member access operators, and if
    # there is a property or method call.  We'll access properties directly, but
    # we'll use reflection to get members from a method call.
    
    # This will hold the "parsed" expression of member references
    $fullExpr = new-object System.Collections.Stack
    # The last member is wildcarded, all others are not
    $member = $memberName + '*'
    # We note isProperty as we go.  It's irrelevant for the last property, but
    # it must be initialized to something.
    $isProperty = $true
    # When we find the root of the expression, we set $value.
    $value = $null
    # If the root of the expression is $_, we won't have a value to use.  Instead,
    # we determine the types $_ could be and use reflection.
    $types = $null
        
    :scanning for (;$idx -ge 0; --$idx)
    {
        $referenceKind = MemberAccessTokenKind $tokens[$idx--]
        
        $node = new-object PSObject -Property @{
            Member = $member
            ReferenceKind = $referenceKind
            IsProperty = $isProperty
        }
        $null = $fullExpr.Push($node)

        $isProperty = $true
        do
        {
            # This loop usually just executes once, but when we find a method argument list, we
            # loop again to get the member name.
            $foundMember = $true
        
            $token = $tokens[$idx]
            switch ($token.Type)
            {
                <#case#> $PSTokenType::Variable
                {
                    if (IsRootToken)
                    {
                        if ($token.Content -eq '_')
                        {
                            # $_ is special.  We need to guess at it's type.  We can try a few things
                            #    * If we know the command, we can check the [outputtype] attributes
                            #    * If the previous pipeline command is an expression, we can check it's
                            #      element types
                            $types = DetermineDollarUnderType $tokens $idx
                        }
                        else
                        {
                            $var = & $GetVariableProxy -Name ($token.Content) -ErrorAction SilentlyContinue
                            if ($null -ne $var -and $null -ne $var.Value)
                            {
                                $value = $var.Value
                            }
                        }
                        break scanning
                    }
                    else
                    {
                        $var = & $GetVariableProxy -Name ($token.Content) -ErrorAction SilentlyContinue
                        if ($null -ne $var -and $null -ne $var.Value)
                        {
                            $member = [string]$var.Value
                        }
                    }
                    break
                }
                <#case#> $PSTokenType::Member
                {
                    $member = $token.Content
                }
                <#case#> $PSTokenType::String
                {
                    if (IsRootToken)
                    {
                        $value = $token.Content
                        break scanning
                    }
                    else
                    {
                        $member = $token.Content
                        break
                    }
                }
                <#case#> $PSTokenType::GroupEnd
                {
                    $start = FindGroupMatch $tokens $idx
                    if ($start -ne -1)
                    {
                        $idx = $start - 1
                        if (IsRootToken)
                        {
                            $token = $tokens[$idx]
                            # We might have an array or hash literal.  We won't
                            # evaluate the members of the array, but we can use
                            # an empty value for completion.
                            if ($token.Content -eq '@{')
                            {
                                $value = @{}
                            }
                            elseif ($token.Content -eq '@(')
                            {
                                $value = @()
                            }
                            break scanning
                        }
                        else
                        {
                            $isProperty = $false
                            $foundMember = $false
                        }
                    }
                    else
                    {
                        break scanning
                    }
                }
                <#case#> $PSTokenType::Type
                {
                    # Must be the root of the expression
                    $value = [type]$token.Content
                    break scanning
                }
            }
        } while (!$foundMember)
    }
    
    $methodFlags = [System.Management.Automation.PSMemberTypes] 'Methods,ParameterizedProperty'
    $propertyFlags = [System.Management.Automation.PSMemberTypes] 'Properties'
    
    while ($fullExpr.Count -gt 1)
    {
        $node = $fullExpr.Pop()
        if ($null -ne $value)
        {
            if ($node.IsProperty)
            {
                if ($node.ReferenceKind -eq 'instance')
                {
                    try { $value = $value.$($node.Member) }
                    catch { break }
                }
                else
                {
                    try { $value = $value::$($node.Member) }
                    catch { break }
                }
            }
            else
            {
                if ($node.ReferenceKind -eq 'instance')
                {
                    $types = $value.psobject.members |
                        Where-Object { $_.Name -eq $node.Member -and $_.MemberType -band $methodFlags } |
                            ForEach-Object {
                                foreach ($overload in $_.OverloadDefinitions)
                                {
                                    # We want the return type.  $overload is just a string.  A space
                                    # seperates the return type from the function name, but that space
                                    # cannot be nested (generics may use spaces in assembly qualified names).
                                    $returnType = ''
                                    $brackets = 0
                                    :loop for ($i = 0; $i -lt $overload.Length; ++$i)
                                    {
                                        switch ($overload[$i])
                                        {
                                            <#case#> ' '
                                            {
                                                if ($brackets -eq 0)
                                                {
                                                    $returnType = $overload.SubString(0, $i)
                                                    break loop
                                                }
                                                break
                                            }
                                            <#case#> '[' { ++$brackets ; break }
                                            <#case#> ']' { --$brackets ; break }
                                        }
                                    }
                                    
                                    if (($returnType = $returnType -as [type]) -ne $null)
                                    {
                                        $returnType
                                    }
                                }
                            } | Sort-Object -Unique
                }
                else
                {
                    $type = if ($value -is [type]) { $value } else { $value.GetType() }
                    $types = $type.GetMethods('public,static') |
                        Where-Object { $_.Name -eq $node.Member } |
                            ForEach-Object {
                                $_.ReturnType
                            } | Sort-Object -Unique
                }                
                
                # We no longer have a value to work with, so clear it
                $value = $null
            }
        }
        elseif ($null -ne $types)
        {
        }
    }
    
    $skipPrefices = @('get_', 'set_', 'add_', 'remove_')
    
    function AppendMemberResult
    {
        [cmdletbinding()]
        param([Parameter(ValueFromPipeline=$true)]$member)
        
        process
        {
            if ($member.Name -notmatch "^([^_]+_)." -or
                $skipPrefices -notcontains $matches[1])
            {                
                $isMethod = $false
                if ($member -is [System.Reflection.MemberInfo])
                {
                    $isMethod = ($member -is [System.Reflection.MethodInfo])
                }
                else
                {
                    $isMethod = $member.MemberType -band $methodFlags
                }
                
                if ($isMethod)
                {
                    AppendResult ($member.Name + '(')
                }
                else
                {
                    AppendResult $member.Name
                }
            }
        }
    }
    
    $memberSort = @(
        @{ Expression = { $_.MemberType -band $methodFlags } },
        'Name'
    )
    $node = $fullExpr.Pop()
    if ($null -ne $value)
    {
        if ($node.ReferenceKind -eq 'instance')
        {
            # Get-Member is not used here because PowerShell will enumerate IEnumerable
            # arguments to cmdlets and functions.  To avoid that, we can get the members
            # this way (extended members and adapted members work just fine this way).
            $value.psobject.members |
                Where-Object { $_.Name -like $node.Member } | 
                    Sort-Object -Property $memberSort | AppendMemberResult
        }
        else
        {
            if ($value -is [type])
            {
                $type = $value
            }
            else
            {
                # Strictly speaking it doesn't make sense to do this, but a future
                # version of the language will probably allow access to static members
                # using an instance on the LHS rather than a type, so complete it anyway.
                $type = $value.GetType()
            }
            $type | Get-Member -Static -Name $node.Member |
                Sort-Object -Property $memberSort | AppendMemberResult
        }
    }
    elseif ($null -ne $types)
    {
        # Must resort to reflection
        foreach ($type in $types)
        {
            $type.GetMembers("public,$($node.ReferenceKind)") |
                Where-Object { $_.Name -like $node.Member -and
                    ($_ -is [System.Reflection.MethodInfo] -or
                     $_ -is [System.Reflection.PropertyInfo]) } |
                    Sort-Object -Property @{ Expression = { $_ -is [System.Reflection.MethodInfo] } },'Name' |
                        AppendMemberResult
        }
    }
}

############################################################################
## Complete an operand
############################################################################
function ExpandOperator 
{
    param([string]$operator)
    
    function DontReplaceToken
    {
        (Get-Variable -Scope 2 -Name firstReplacementOffset).Value += $operator.Length
        (Get-Variable -Scope 2 -Name firstReplacementLength).Value = 0        
    }
    
    switch ($operator)
    {
    <#case#> ','
        {
            # TODO - we could be completing a method argument or something else, don't assume it's a command argument
            DontReplaceToken
            ExpandCommandArgument ''
            break
        }
    <#case#> { $_ -eq '.' -or $_ -eq '::' }
        {
            DontReplaceToken
            ExpandMember ''
            break
        }
    }
}

############################################################################
## Complete a keyword
############################################################################
function ExpandKeyword
{
    param($keyword)
    
    switch ($keyword)
    {
        <#case#> "begin"    { AppendResult "begin {}"; break }
        <#case#> "catch"    { AppendResult "catch {}"; break }
        <#case#> "data"     { AppendResult "data {}"; break }
        <#case#> "do"       { AppendResult "do {} while ()"
                              AppendResult "do {} until ()"
                              break }
        <#case#> "dynamicparam"
                            { AppendResult "dynamicparam {}"; break }
        <#case#> "else"     { AppendResult "else {}"; break }
        <#case#> "elseif"   { AppendResult "elseif () {}"; break }
        <#case#> "end"      { AppendResult "end {}"; break }
        <#case#> "filter"   { AppendResult "filter {}"; break }
        <#case#> "finally"  { AppendResult "finally {}"; break }
        <#case#> "for"      { AppendResult "for (; ;) {}"; break }
        <#case#> "foreach"  { AppendResult "foreach ( in ) {}"; break }
        <#case#> "function" { AppendResult "function { param() }"; break }
        <#case#> "if"       { AppendResult "if () {}"; break }
        <#case#> "param"    { AppendResult "param()"; break }
        <#case#> "process"  { AppendResult "process {}"; break }
        <#case#> "switch"   { AppendResult "switch () {}"; break }
        <#case#> "trap"     { AppendResult "trap {}"; break }
        <#case#> "try"      { AppendResult "try {} catch {}"; break }
        <#case#> "while"    { AppendResult "while () {}"; break }
    }
}

############################################################################
## Complete a comment
############################################################################
function ExpandComment
{
    param($comment)
    
    # Remove comment markers
    if ($comment[0] -eq '#')
    {
        $pattern = $comment.Substring(1)
    }
    else
    {
        $pattern = $comment.SubString(2, $comment.Length - 4)
    }
    
    if ($pattern -match '^[0-9]+$')
    {
        Get-History -ea SilentlyContinue -Id $pattern |
            ForEach-Object { $_.CommandLine } | AppendResult
    }
    else
    {
        $pattern = '*' + $pattern + '*'
        Get-History -Count 32767 |
            Where-Object { $_.CommandLine -like $pattern } |
                Sort-Object -Descending Id |
                    ForEach-Object { $_.CommandLine } | AppendResult
    }    
}

############################################################################
## A stub for expansion on tokens that there is nothing we can expand
############################################################################
function NoExpansion {}

############################################################################
## The primary entry point to this module to do any tab expansion
############################################################################
function TabExpansion2
{
    [CmdletBinding()]
    param([string]$line, [int]$cursor)

    Set-StrictMode -v 2
    
    $results = new-object System.Collections.ObjectModel.Collection[string]
    
    $PSTokenType = [System.Management.Automation.PSTokenType]

    $tokenHandlers = @(
        <#Unknown#>            'NoExpansion',
        <#Command#>            'ExpandCommand',
        <#CommandParameter#>   'ExpandCommandParameter',
        <#CommandArgument#>    'ExpandCommandArgument',
        <#Number#>             'NoExpansion',
        <#String#>             'NoExpansion',
        <#Variable#>           'ExpandVariable',
        <#Member#>             'ExpandMember',
        <#LoopLabel#>          'NoExpansion',
        <#Attribute#>          'NoExpansion',
        <#Type#>               'ExpandType',
        <#Operator#>           'ExpandOperator',
        <#GroupStart#>         'NoExpansion',
        <#GroupEnd#>           'NoExpansion',
        <#Keyword#>            'ExpandKeyword',
        <#Comment#>            'ExpandComment',
        <#StatementSeparator#> 'NoExpansion',
        <#NewLine#>            'NoExpansion',
        <#LineContinuation#>   'NoExpansion',
        <#Position#>           'NoExpansion'
    )

    
    $errors = $null
    $tokens = [system.management.automation.psparser]::tokenize($line, [ref]$errors)
    
    # Find the token the cursor is in
    
    for ($cursorTokenIndex = 0; $cursorTokenIndex -lt $tokens.Count; ++$cursorTokenIndex)
    {
        if ($cursor -le ($tokens[$cursorTokenIndex].Start + $tokens[$cursorTokenIndex].Length))
        {
            break;
        }
    }
    
    :plentyOfResults do
    {
        if ($cursorTokenIndex -lt $tokens.Count)
        {
            $firstReplacementOffset = $tokens[$cursorTokenIndex].Start
            $firstReplacementLength = $tokens[$cursorTokenIndex].Length
        
            & $tokenHandlers[$tokens[$cursorTokenIndex].Type] $tokens[$cursorTokenIndex].Content
            
        }
        else
        {
            if ($errors.Count -eq 0)
            {
                # The cursor is not in any token.  For now, assume it's a command argument.  This
                # won't always be true though, we may be in some pure expression, or, maybe worse,
                # in some sub expression.
                $firstReplacementOffset = $line.Length
                $firstReplacementLength = 0
        
                ExpandCommandArgument ''
            }
            else
            {
                # Assume the cursor is in some incomplete token.  Attempt to figure out what that token
                # might be by scanning forwards after the last token for the first non-whitespace character.
                
                $i = if ($tokens.Count -gt 0) { $tokens[$tokens.Count-1].Start + $tokens[$tokens.Count-1].Length } else { 0 }
                while ($i -lt $line.Length -and [char]::IsWhiteSpace($line[$i]))
                {
                    ++$i
                }
                
                if ($line[$i] -eq '[')
                {
                    $firstReplacementOffset = $i
                    $firstReplacementLength = ($line.Length - $i)
        
                    ExpandType $line.SubString($i)
                }
            }
        }
    } while ($false)
    
    $result = Add-Member -InputObject $results -Name FirstReplacementOffset -Type NoteProperty -Value $firstReplacementOffset -PassThru |
        Add-Member -Name FirstReplacementLength -Type NoteProperty -Value $firstReplacementLength -PassThru
    ,$result
}

############################################################################
## Create a DataTable that is used for faster searching
############################################################################
function New-DataTable
{
    param($tableName, [hashtable[]]$columns)
    
    $table = new-object System.Data.DataTable $tableName
    foreach ($column in $columns)
    {
        $table.Columns.Add((new-object System.Data.DataColumn -Property $column))
    }
    $table.PrimaryKey = @($table.Columns[0])

    Write-Output (,$table)
}

############################################################################
## Load data into the data table (load from a xml string for speed)
############################################################################
function Fill-DataTable
{
    param([System.Data.DataTable]$table, $data)
    
    $null = $table.ReadXml((New-Object System.IO.StringReader $data))
}

############################################################################
## Search the data table
############################################################################
function Search-DataTable
{
    param($table, $property, $pattern, $select)
    
    # TODO: A DataTable wildcard only supports * at the start or
    #    end of the pattern.  We will also need to escape % as it
    #    is a valid wildcard character for DataTable but not PowerShell.
    $table.Select("$property LIKE '$pattern'") | ForEach-Object $select
}

############################################################################
##
############################################################################
function Save-DataTable
{
    param($dataTable)
    
    $appData = [System.Environment]::GetFolderPath('LocalApplicationData')
    $folder = "$appData\Microsoft\Windows\WindowsPowerShell"
    if (!(Test-Path $folder))
    {
        $null = New-Item -ItemType Directory -Force $folder
    }
    
    $path = "$folder\TabExpansion2-$($dataTable.TableName).xml"
    if (Test-Path $path)
    {
        Remove-Item $path -Force -ErrorAction SilentlyContinue
    }
    if (!(Test-Path $path))
    {
        $dataTable.WriteXml($path, [System.Data.XmlWriteMode]::WriteSchema) 
    }
}

############################################################################
##
############################################################################
function Load-DataTable
{
    param($tableName)
    
    $appData = [System.Environment]::GetFolderPath('LocalApplicationData')
    $folder = "$appData\Microsoft\Windows\WindowsPowerShell"
    $path = "$folder\TabExpansion2-${tableName}.xml"
    if (test-path $path)
    {
        $table = new-object System.Data.DataTable
        $null = $table.ReadXml($path)
        
        Write-Output (,$table)
    }
    
    Write-Output $null
}

############################################################################
## Build the type cache.
##
## This function isn't normally invoked directly - it is normally invoked
## in a different runspace
############################################################################
function BuildTypeCache
{
    ## Generate a table for the list of accelerators
        
    if ($null -eq ($acceleratorsTable = Load-DataTable Accelerators))
    {
        $columns = @{DataType=[string]; ColumnName='Accelerator'; ReadOnly=$true; Unique=$true}
        $acceleratorsTable = New-DataTable Accelerators $columns
        # Use reflection rather than hard code the list of accelerators.  Technique published here:
        # http://www.nivot.org/2008/12/25/ListOfTypeAcceleratorsForPowerShellCTP3.aspx
        $acceleratorsList = [System.Type]::GetType("System.Management.Automation.TypeAccelerators")::Get.Keys    
        
        Fill-DataTable $acceleratorsTable @"
          <NewDataSet>
            $($acceleratorsList | ForEach-Object { "<Accelerators><Accelerator>$_</Accelerator></Accelerators>" })
          </NewDataSet>
"@

        Save-DataTable $acceleratorsTable
    }

    if ($null -eq ($namespacesTable = Load-DataTable Namespaces) -or
        $null -eq ($fulltypesTable = Load-DataTable FullTypes) -or
        $null -eq ($typeTable = Load-DataTable Types))
    {
        ## Generate a list of all exported types.  We'll manipulate this list a few ways
        ## to make expansion of types useful.

        $allTypeNames = foreach ($assem in [System.Appdomain]::CurrentDomain.GetAssemblies()) {
            foreach ($type in $assem.GetExportedTypes()) {
                $type.FullName
            }
        }
        
        # When expanding types, we also want to match just namespaces.  Generate that list (as a hash to
        # avoid duplicates up front as there will be many duplicates.)
        $namespaces = @{}
        $allTypeNames | ForEach-Object {
            if ($_ -match '^(.*)\.[^.]+$')
            {
                ++$namespaces[$matches[1]]
            }
        }
        
        $columns = @{DataType=[string]; ColumnName='Namespace'; ReadOnly=$true; Unique=$true}
        $namespacesTable = New-DataTable Namespaces $columns
        # Add a dot because namespaces are incomplete and will require the dot for a complete type name
        $namespacesList = $namespaces.Keys | ForEach-Object { $_ + '.' }
        Fill-DataTable $namespacesTable @"
          <NewDataSet>
            $($namespacesList | Sort-Object | ForEach-Object { "<Namespaces><Namespace>$_</Namespace></Namespaces>" })
          </NewDataSet>
"@
        
        # Types are handled 2 different ways.  First, we will have a table with the full type names.  Second,
        # we'll have a mapping from the bare typename (no namespace) to a list of full types with that name.
        $typehash = @{}
        $fulltypesList = foreach ($typename in $allTypeNames) {
            # Type names with a backtick followed by one or more digits is, by convention, a generic.
            # During expansion, most users will not want or expect to see the `num, so remove that,
            # and add a open square bracket as that will be necessary in a complete type.
            if ($typename -match '^(.*)`[0-9]+$')
            {
                Write-Output ($matches[1] + '[')
            }
            
            # Now, split the namespace and the type name so we can index on the type name.  We
            # are building a list of full typenames that all share a common type name (w/o the namespace)
            if ($typename -match '^(.*[.+])([^.`]+)(`[0-9]+)?$')
            {
                $namespace = $matches[1]
                $baretype = $matches[2]
                $isgeneric = $matches[3] -ne $null
                
                $list = $typehash[$baretype]
                if ($null -eq $list)
                {
                    $list = New-Object System.Collections.Generic.List[string]
                    $typehash[$baretype] = $list
                }
                
                if ($isgeneric)
                {
                    # The type is a generic.  Record the name w/o the backtick, adding the square bracket.
                    $list.Add($namespace + $baretype + '[')
                }
                $list.Add($typename)
            }
            
            # Always emit the full name, even if it is a generic.  In uncommon cases, you may want
            # generic type.
            Write-Output $typename
        }
        $columns = @{DataType=[string]; ColumnName='FullType'; ReadOnly=$true; Unique=$true}
        $fulltypesTable = New-DataTable FullTypes $columns
        Fill-DataTable $fulltypesTable @"
          <NewDataSet>
            $($fullTypesList | Sort-Object -Unique | ForEach-Object { "<FullTypes><FullType>$_</FullType></FullTypes>" })
          </NewDataSet>
"@
        
        $columns = @{DataType=[string]; ColumnName='Type'; ReadOnly=$true; Unique=$true},
                   @{DataType=[string[]]; ColumnName='FullType'; ReadOnly=$true}
        $typeTable = New-DataTable Types $columns
        Fill-DataTable $typeTable @"
          <NewDataSet>
            $($typeHash.GetEnumerator() | ForEach-Object { @"
              <Types>
                <Type>$($_.Key)</Type>
                <FullType xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
                  $($_.Value | Sort-Object -Unique | ForEach-Object { "<string>$_</string>" })
                </FullType>
              </Types>
"@
            })
          </NewDataSet>
"@

        Save-DataTable $namespacesTable
        Save-DataTable $fulltypesTable
        Save-DataTable $typeTable
    }
    
    $typeCache = New-Object PSObject -Property @{
        accelerators=$acceleratorsTable
        namespaces=$namespacesTable
        fulltypes=$fulltypesTable
        typehash=$typeTable
    }

    Write-Output $typeCache
}

############################################################################
## Build the cache of prog ids for the -ComObject parameter to New-Object
##
## This function isn't normally invoked directly - it is normally invoked
## in a different runspace
############################################################################
function BuildProgIdCache
{
    if ($null -eq ($progIdTable = Load-DataTable ProgIds))
    {
        $progIds = Get-ItemProperty 'microsoft.powershell.core\registry::HKEY_CLASSES_ROOT\CLSID\*\ProgId' |
            ForEach-Object { $_."(default)" }

        $columns = @{DataType=[string]; ColumnName='ProgId'; ReadOnly=$true; Unique=$true}
        $progIdTable = New-DataTable ProgIds $columns
        Fill-DataTable $progIdTable @"
          <NewDataSet>
            $($progIds | Sort-Object -Unique | ForEach-Object { "<ProgIds><ProgId>$_</ProgId></ProgIds>" })
          </NewDataSet>
"@
        Save-DataTable $progIdTable
    }

    $progIdCache = New-Object PSObject -Property @{
        progids=$progIdTable
    }
    Write-Output $progIdCache
}

############################################################################
## Build the list of wmi classes for the -Class parameter to the various
## WMI cmdlets.
############################################################################
function BuildWMIClassesCache
{
    if ($null -eq ($wmiTable = Load-DataTable WMIClasses))
    {
        $wmiClasses = Get-WmiObject -List -Recurse | ForEach-Object { $_.Name }
        $columns = @{DataType=[string]; ColumnName='WMIClass'; ReadOnly=$true; Unique=$true}
        $wmiClassesTable = New-DataTable WMIClasses $columns        
        Fill-DataTable $wmiClassesTable @"
          <NewDataSet>
            $($wmiClasses | Sort-Object -Unique | ForEach-Object { "<WMIClasses><WMIClass>$_</WMIClass></WMIClasses>" })
          </NewDataSet>
"@
        Save-DataTable $wmiTable
    }
    
    $wmiClassesCache = New-Object PSObject -Property @{
        wmiclasses=$wmiClassesTable
    }
    Write-Output $wmiClassesCache
}

############################################################################
## Create helper methods for things that can't be implemented in script
############################################################################
function AddHelperMethods
{
    if (('TabExpansion2.NativeMethods' -as [type]) -eq $null)
    {
        $null = Add-Type @'
            using System;
            using System.Runtime.InteropServices;
            using System.Collections;

            namespace TabExpansion2
            {
                public static class NativeMethods
                {
                    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
                    public struct SHARE_INFO_0
                    {
                        public string netname;
                    }

                    public const int MAX_PREFERRED_LENGTH = -1;
                    public const int NERR_Success = 0;
                    public const int ERROR_MORE_DATA = 234;

                    [DllImport("Netapi32.dll", CharSet = CharSet.Unicode)]
                    public static extern int NetShareEnum(string serverName, int level, out IntPtr bufptr, int prefMaxLen,
                        out uint entriesRead, out uint totalEntries, ref uint resumeHandle);

                    public static ArrayList GetFileShares(string machine)
                    {
                        IntPtr shBuf;
                        uint numEntries;
                        uint totalEntries;
                        uint resumeHandle = 0;
                        int result = NetShareEnum(machine, 0, out shBuf,
                            MAX_PREFERRED_LENGTH, out numEntries, out totalEntries, ref resumeHandle);

                        ArrayList shares = new ArrayList();
                        if (result == NERR_Success || result == ERROR_MORE_DATA)
                        {
                            for (int i = 0; i < numEntries; ++i)
                            {
                                IntPtr curInfoPtr = (IntPtr)((long)shBuf + (Marshal.SizeOf(typeof(SHARE_INFO_0)) * i));
                                SHARE_INFO_0 shareInfo = (SHARE_INFO_0)Marshal.PtrToStructure(curInfoPtr, typeof(SHARE_INFO_0));

                                shares.Add(shareInfo.netname);
                            }
                        }
                        return shares;
                    }
                }
            }
'@
    }
}

############################################################################
## Generate the list of types for typename completion
############################################################################
function DoBackgroundInitialization
{
    # TODO - add event handler for assembly loads to repopulate the types
    # TODO - add wmi registry event handler to update class
    $script:typeCache = $null
    $script:progIdsCache = $null
    $script:BackgroundInitialization_Job = [PowerShell]::Create()
    
    $BackgroundInitialization_Job.AddScript(@"
        Import-Module $($myInvocation.ScriptName) -Args $true
        BuildTypeCache
        BuildProgIdCache
        BuildWmiClassesCache
        AddHelperMethods
"@)
    
    $script:BackgroundInitialization_AsyncResult = $BackgroundInitialization_Job.BeginInvoke()
}

############################################################################
## Check the background job to see if it is complete.  If so, set the
## results.
############################################################################
function ReceiveBackgroundResults
{
    if ($BackgroundInitialization_AsyncResult.IsCompleted)
    {
        $script:TypeCache,$script:progIdCache,$script:WmiClassesCache =
            $BackgroundInitialization_Job.EndInvoke($BackgroundInitialization_AsyncResult)
        $script:BackgroundInitialization_AsyncResult = $null
        $script:BackgroundInitialization_Job = $null
    }
}

############################################################################
## Return the type cache, checking the background job first
############################################################################
function GetTypeCache
{
    if ($TypeCache -eq $null)
    {
        ReceiveBackgroundResults
    }
    
    Write-Output $TypeCache
}

############################################################################
## Return the prog id cache, checking the background job first
############################################################################
function GetProgIdCache
{
    if ($progIdCache -eq $null)
    {
        ReceiveBackgroundResults
    }
    
    Write-Output $progIdCache
}

############################################################################
## Return the prog id cache, checking the background job first
############################################################################
function GetWmiClassesCache
{
    if ($wmiClassesCache -eq $null)
    {
        ReceiveBackgroundResults
    }
    
    Write-Output $wmiClassesCache
}

#
# .SYNOPSIS
#    Add a custom handler for argument completion.
#
# .DESCRIPTION
#    Argument completion can be customized for:
#
#      * All parameters with a given name, such as 'Path' or 'TypeName'
#      * A specific parameter for a given command, such as the Path parameter
#        for the Set-Location command. To specify this parameter, you
#        would pass 'Set-Location:Path'.
#
#    A custom handler will be passed two arguments:
#
#      * the possibly empty argument already specified
#      * a boolean value - $true if the parameter is named, $false otherwise.
#           This is useful when an argument requires the parameter name, but
#           is being specified positionally (an uncommon situation, but one
#           example is the ComObject parameter to New-Object.)
#
# .EXAMPLE
#
#    Add-ArgumentCompleter 'Remove-Module:Name' {
#        Get-Module -Name ($arg[0]+'*') | % { $_.Name }
#    }
#
function Add-ArgumentCompleter
{
    param([Parameter(ValueFromPipeline=$true)][string[]]$parameter,
          [scriptblock]$sb)
    
    process
    {
        foreach ($param in $parameter)
        {
            $argumentCompleter.Add($param, $sb)
        }
    }
}

############################################################################
## Set the built-in argument completers
############################################################################
function PopulateArgumentCompleters
{
    $script:argumentCompleter = @{}

    Add-ArgumentCompleter TypeName {
        param($type)
        
        ExpandType $type
    }
    
    Add-ArgumentCompleter ComObject {
        param($progid, $isNamed)
        
        $table = GetProgIdCache
        Search-DataTable $table.progids ProgId "$progid*" { $_.progid } |
            ForEach-Object {
                if ($isNamed)
                {
                    $_
                }
                else
                {
                    "-ComObject " + $_
                }
            }
    }

    # cd should only complete on containers.  Note we don't also set -LiteralPath
    #  because that doubles the work for no gain.
    Add-ArgumentCompleter ('Set-Location:Path','Push-Location:Path') {
        param($path)
        
        ExpandFileName $path { Test-Path -LiteralPath $_ -PathType Container }
    }

    Add-ArgumentCompleter Import-Module:Name {
        param($module)
        
        # Explicitly call AppendResult because ExpandFileName will append results
        # and we want the non-file modules to appear first
        
        # TODO - filter out modules already loaded
        Get-Module -ListAvailable -Name $module    | ForEach-Object { $_.Name } | Sort-Object | AppendResult
        Get-Module -ListAvailable -Name "$module*" | ForEach-Object { $_.Name } | Sort-Object | AppendResult
        ExpandFileName $module { ".psm1",".psd1",".dll" -contains [System.IO.Path]::GetExtension($_) }
    }

    Add-ArgumentCompleter ('Remove-Module:Name','Get-Module:Name') {
        param($module)
        
        Get-Module -Name $module    | ForEach-Object { $_.Name } | Sort-Object
        Get-Module -Name "$module*" | ForEach-Object { $_.Name } | Sort-Object
    }

    Add-ArgumentCompleter Verb {
        param($verb)
        
        Get-Verb -Verb $verb    | ForEach-Object { $_.Verb } | Sort-Object
        Get-Verb -Verb "$verb*" | ForEach-Object { $_.Verb } | Sort-Object
    }
    
    Add-ArgumentCompleter 'Stop-Process:Name' {
        param($name)
        
        Get-Process -Name "$name*" | ForEach-Object { $_.ProcessName } | Sort-Object
    }
    
    Add-ArgumentCompleter 'Add-PSSnapin:Name' {
        param($name)
        
        Get-PSSnapin -Registered -Name "$name*" | ForEach-Object { $_.Name } | Sort-Object
    }
    
    Add-ArgumentCompleter 'Get-PSSnapin:Name' {
        param($name)
        
        Get-PSSnapin -Name "$name*" | ForEach-Object { $_.Name } | Sort-Object
    }
    
    Add-ArgumentCompleter 'Add-Type:UsingNamespace' {
        param($namespace)
        
        $TypeCache = GetTypeCache
        
        if ($null -ne $TypeCache)
        {
            $TypeCache.Namespaces -like "$namespace*" | ForEach-Object { $_.Trim('.') } | Sort-Object
        }
    }
    
    Add-ArgumentCompleter 'Clear-EventLog:LogName','Get-EventLog:LogName',
                          'Limit-EventLog:LogName','Remove-EventLog:LogName',
                          'Write-EventLog:LogName' {
        param($logname)
        
        Get-EventLog -List |
            Where-Object { $_.Log -like "$logname*" } |
                ForEach-Object { $_.Log } | Sort-Object | QuoteArgumentIfNecessary
    }
    
    Add-ArgumentCompleter 'Get-WinEvent:LogName' {
        param($logname)
        
        Get-WinEvent -ListLog "$logname*" | ForEach-Object { $_.LogName } | Sort-Object | QuoteArgumentIfNecessary
    }
    
    Add-ArgumentCompleter 'Clear-Variable:Name','Get-Variable:Name','Remove-Variable:Name','Set-Variable:Name' {
        param($name)
        
        & $GetVariableProxy -Name "$name*" | ForEach-Object { $_.Name } | Sort-Object
    }
    
    Add-ArgumentCompleter 'Get-WmiObject:Class','Invoke-WmiMethod:Class','Register-WmiEvent:Class',
                          'Remove-WmiObject:Class','Set-WmiInstance:Class' {
        param($class)
        
        $wmiClassesCache = GetWmiClassesCache
        if ($null -ne $wmiClassesCache)
        {
            Search-DataTable $wmiClassesCache.wmiclasses WMIClass "$class*" { $_.WMIClass } | Sort-Object
        }
    }
    
    Add-ArgumentCompleter 'Get-Help:Name','Help:Name' {
        param($name)
        
        ExpandCommand $name @{CommandType="Alias,Function,Filter,Cmdlet,ExternalScript,Script"}
        $topics = if ($name -match '^about') { "$name*" } else { "about_$name*" }
        & $GetChildItemProxy "$PSHOME\$PSUICulture\$topics" |
            ForEach-Object {
                $_.Name -replace '.help.txt',''
            }
        Get-PSProvider | Where-Object { $_.Name -match "$name*" } | ForEach-Object { $_.Name }
    }
}

############################################################################
## Set the built-in native command argument (and parameter) completers.
############################################################################
function PopulateNativeCommandCompleters
{
    $script:nativeCommandArgumentCompleters = @{}
    
    $nativeCommandArgumentCompleters["net.exe"] = {
        param($arg)
        
        "ACCOUNTS", "COMPUTER", "CONFIG", "CONTINUE", "FILE", "GROUP",
        "HELP", "HELPMSG", "LOCALGROUP", "PAUSE", "PRINT", "SESSION",
        "SHARE", "START", "STATISTICS", "STOP", "TIME", "USE", "USER", "VIEW" |
            Where-Object {
                $_ -like "$arg*"
            }        
    }
}

############################################################################
## The module "Main", initialize some things for the module
############################################################################

if ($forBackgroundInitialization)
{
    Export-ModuleMember BuildTypeCache,BuildProgIdCache,BuildWMIClassesCache,AddHelperMethods
    return
}

DoBackgroundInitialization
PopulateArgumentCompleters
PopulateNativeCommandCompleters

# Set up so we can restore the old tab expansion when this module is unloaded
$oldTabExpansion = $global:oldTabExpansion
Remove-Variable -Scope 1 oldTabExpansion
$MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
    Set-Item -Path function:global:TabExpansion $oldTabExpansion
}

Export-ModuleMember Add-ArgumentCompleter
