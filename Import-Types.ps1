#############
# Import-Types.ps1
# 
# Allows you to import types 
# 
# Taken from: 
#    http://blogs.msdn.com/richardb/archive/2007/02/21/add-types-ps1-poor-man-s-using-for-powershell.aspx
#############

param(
    [string] $assemblyName = $(throw 'assemblyName is required'),
    [object] $object
)

process {
	if ($_) {
		$object = $_
	}
	
	if (! $object) {
		throw 'must pass an -object parameter or pipe one in'
	}
	
	# load the required dll
	$assembly = [System.Reflection.Assembly]::LoadWithPartialName($assemblyName)
	
	# add each type as a member property
	$assembly.GetTypes() | 
		where { 
			$_.IsPublic -and
			!$_.IsSubclassOf( [Exception] ) -and
			!$_.IsSubclassOf( [MulticastDelegate] ) -and
			!$_.IsSubclassOf( [EventArgs] )
		} | foreach { 
				add-member noteproperty $_.name $_ -inputobject $object
		}
}
