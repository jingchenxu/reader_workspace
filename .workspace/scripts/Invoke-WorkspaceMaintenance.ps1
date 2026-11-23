param(
  [ValidateSet('report','cleanup')][string]$Mode = 'report',
  [int]$RetentionDays = 14,
  [string]$Workspace = (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
)
$now = Get-Date
$cutoff = $now.AddDays(-$RetentionDays)
$patterns = @('*.log','*.out','*.err','tmp-*.png','tmp-*.xml')
$excluded = @('\.git\','\.workspace\','\node_modules\','\.cargo-cache\')
$files = Get-ChildItem -LiteralPath $Workspace -Recurse -File -Force -ErrorAction SilentlyContinue |
  Where-Object { $_.LastWriteTime -lt $cutoff -and ($patterns -contains $_.Name -or $_.Extension -in '.log','.out','.err') } |
  Where-Object { $path=$_.FullName; -not ($excluded | Where-Object { $path -match [regex]::Escape($_) }) }
$report = [ordered]@{generatedAt=$now.ToString('o'); mode=$Mode; retentionDays=$RetentionDays; count=$files.Count; bytes=[int64](($files | Measure-Object Length -Sum).Sum); files=@($files | ForEach-Object {[ordered]@{path=$_.FullName.Substring($Workspace.Length+1); length=$_.Length; lastWriteTime=$_.LastWriteTime.ToString('o')}})}
$out = Join-Path $Workspace '.workspace\snapshots\maintenance-report.json'
$report | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 $out
if($Mode -eq 'cleanup') { $files | Remove-Item -Force }
Write-Output "Report: $out"
Write-Output "Mode=$Mode Count=$($report.count) Bytes=$($report.bytes)"
