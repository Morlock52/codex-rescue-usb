function ConvertTo-CodexRescueHtml {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Assessment,

        [string]$Title = 'Codex Rescue device health report'
    )

    $encode = {
        param([AllowNull()][object]$Value)
        [System.Net.WebUtility]::HtmlEncode([string]$Value)
    }
    $statusClass = @{
        Healthy = 'healthy'
        Warning = 'warning'
        Failed = 'failed'
        NotTested = 'not-tested'
    }
    $deviceRows = @()
    if ($Assessment.PSObject.Properties.Name -contains 'DeviceSummary' -and $Assessment.DeviceSummary) {
        foreach ($property in $Assessment.DeviceSummary.PSObject.Properties) {
            $deviceRows += '<tr><th>{0}</th><td>{1}</td></tr>' -f (& $encode $property.Name), (& $encode $property.Value)
        }
    }
    $checkCards = @()
    foreach ($check in @($Assessment.Checks)) {
        $class = $statusClass[[string]$check.Status]
        if (!$class) { $class = 'not-tested' }
        $detailJson = $check.Data | ConvertTo-Json -Depth 12
        $checkCards += @"
<section class="check $class">
  <div class="check-heading"><h3>$(& $encode $check.CheckName)</h3><span>$(& $encode $check.Status)</span></div>
  <p>$(& $encode $check.Summary)</p>
  <details><summary>Structured detail</summary><pre>$(& $encode $detailJson)</pre></details>
</section>
"@
    }
    $sanitizedLabel = if ($Assessment.PSObject.Properties.Name -contains 'SanitizedForCodex' -and $Assessment.SanitizedForCodex) {
        'Sanitized escalation view'
    }
    else {
        'Local operator view - contains device identifiers'
    }
    $score = if ($Assessment.PSObject.Properties.Name -contains 'HealthScore') { $Assessment.HealthScore } else { 'N/A' }
    $generated = if ($Assessment.PSObject.Properties.Name -contains 'GeneratedAtUtc') { $Assessment.GeneratedAtUtc } else { (Get-Date).ToUniversalTime().ToString('o') }

    @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(& $encode $Title)</title>
<style>
:root { color-scheme: light; font-family: "Segoe UI", Arial, sans-serif; background: #f4f7fb; color: #172033; }
body { margin: 0; }
header { background: linear-gradient(135deg, #102b4e, #176b87); color: white; padding: 32px clamp(20px, 5vw, 64px); }
header h1 { margin: 0 0 8px; font-size: clamp(26px, 4vw, 42px); }
header p { margin: 4px 0; color: #d9eef5; }
main { max-width: 1180px; margin: 0 auto; padding: 28px 20px 56px; }
.notice { border-left: 5px solid #176b87; background: white; padding: 16px 18px; margin-bottom: 22px; box-shadow: 0 6px 24px #19324d12; }
.score { display: inline-grid; place-items: center; min-width: 130px; min-height: 92px; border-radius: 16px; background: #102b4e; color: white; font-size: 34px; font-weight: 700; margin: 8px 0 24px; }
.score small { display: block; font-size: 12px; font-weight: 500; letter-spacing: .08em; text-transform: uppercase; }
table { border-collapse: collapse; width: 100%; background: white; box-shadow: 0 6px 24px #19324d12; margin-bottom: 24px; }
th, td { text-align: left; padding: 11px 14px; border-bottom: 1px solid #e5ebf1; vertical-align: top; }
th { width: 34%; color: #44536a; }
.checks { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 16px; }
.check { border-top: 5px solid #7b8798; background: white; border-radius: 10px; padding: 16px; box-shadow: 0 6px 24px #19324d12; }
.check.healthy { border-color: #16845b; } .check.warning { border-color: #d39a13; } .check.failed { border-color: #c13b3b; } .check.not-tested { border-color: #7b8798; }
.check-heading { display: flex; justify-content: space-between; gap: 12px; align-items: baseline; }
.check-heading h3 { margin: 0; } .check-heading span { font-weight: 700; }
details { margin-top: 12px; } summary { cursor: pointer; color: #176b87; }
pre { white-space: pre-wrap; overflow-wrap: anywhere; background: #f5f7fa; padding: 12px; border-radius: 7px; font-size: 12px; }
footer { color: #5d697a; margin-top: 32px; font-size: 13px; }
</style>
</head>
<body>
<header>
  <h1>$(& $encode $Title)</h1>
  <p>$(& $encode $sanitizedLabel)</p>
  <p>Generated $(& $encode $generated)</p>
</header>
<main>
  <div class="notice"><strong>Read-only assessment.</strong> No repair or cloud write action was performed. Review all findings locally before sharing or using Codex.</div>
  <div class="score"><small>Health score</small>$(& $encode $score)/100</div>
  <h2>Device summary</h2>
  <table>$($deviceRows -join "`n")</table>
  <h2>Diagnostic checks</h2>
  <div class="checks">$($checkCards -join "`n")</div>
  <footer>Codex analyzes and recommends. PowerShell performs controlled actions. The technician remains responsible for approval.</footer>
</main>
</body>
</html>
"@
}
