$hgsummary = hg summary --quiet 2>&1
if (! $? ) { return }

set-alias ?: Invoke-Ternary
filter Invoke-Ternary ([scriptblock]$decider, [scriptblock]$ifTrue, [scriptblock]$ifFalse) 
{
   if (& $decider) { 
      & $ifTrue
   } else { 
      & $ifFalse 
   }
}

#
# looks like:
#	commit: 1 modified, 1 added, 1 deleted, 2 unknown
#
if ($hgsummary[1] -match @"
(?x)
	^
	commit:
		(
			\s
			(?<modified>\d)
			\s
			modified,?
		)?
		(
			\sh
			(?<added>\d)
			\s
			added,?
		)?
		(
			\s
			(?<deleted>\d)
			\s
			deleted,?
		)?
		(
			\s
			(?<unknown>\d)
			\s
			unknown
		)?
		(
			\s
			(?<clean> \(clean\)0)
		)?
	.*
	$
"@
) {
    if ($matches['clean']) {
        "[clean]"
    } else {
        if ($matches['modified']) { $modifiedCount = $matches['modified'] } else { $modifiedCount = 0 }
        if ($matches['added']) { $addedCount = $matches['added'] } else { $addedCount = 0 }
        if ($matches['deleted']) { $deletedCount = $matches['deleted'] } else { $deletedCount = 0 }
        '[~{0} +{1} -{2}]' -f $modifiedCount, $addedCount, $deletedCount
    }
}
