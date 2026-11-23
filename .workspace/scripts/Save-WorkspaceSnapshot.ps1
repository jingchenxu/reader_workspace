param([string]$Workspace = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)))
$root = git -C $Workspace rev-parse --show-toplevel 2>$null
$sha = git -C $Workspace rev-parse HEAD 2>$null
$status = @(git -C $Workspace status --short)
$snapshot = [ordered]@{generatedAt=(Get-Date).ToString('o'); workspace=$Workspace; gitRoot=$root; sha=$sha; branch=(git -C $Workspace branch --show-current); clean=($status.Count -eq 0); status=$status; projects=@()}
Get-ChildItem -LiteralPath $Workspace -Directory | Where-Object Name -notin @('.git','.workspace') | ForEach-Object { $p=$_.FullName; $snapshot.projects += [ordered]@{id=$_.Name; path=$_.Name; exists=$true} }
$out=Join-Path $Workspace ('.workspace\snapshots\workspace-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.json')
$snapshot | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 $out
$snapshot | ConvertTo-Json -Depth 6
Write-Output "Snapshot: $out"
