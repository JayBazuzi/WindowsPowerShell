param (
	[Switch] $verbose
)

Set-PSDebug -strict

if ($verbose) { $verbosePreference = "continue" }

trap { break; }


# Load TFS
[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.Client")
[void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.TeamFoundation.VersionControl.Client")

$localWorkspaceInfos = [Microsoft.TeamFoundation.VersionControl.Client.Workstation]::Current.GetAllLocalWorkspaceInfo() | where { $_.Computer -eq $env:COMPUTERNAME } 

"Found {0} workspaces to back up" -f $localWorkspaceInfos.Count | Write-Verbose 

[string] $datestamp = (Get-Date).ToString("u").Replace(":", ".").Replace("/", ".")	

$localWorkspaceInfos | % {

	$workspaceInfo = $_

	pushd $workspaceInfo.MappedPaths[0]

	[string] $shelvesetName = 'ZZZ - {0} at {1}' -f $workspaceInfo.Name,$datestamp 

	"" | Write-Output
	"------ Saving changes to workspace '{0}' at '{1}' to shelveset '{2}'" -f $workspaceInfo.Name,$pwd,$shelvesetName | Write-Output

	tf shelve /noprompt $shelvesetName | Out-Null

	popd
}

