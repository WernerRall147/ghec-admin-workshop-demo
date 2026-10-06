<#
.SYNOPSIS
    Searches the organization or enterprise audit log through the REST API.

.DESCRIPTION
    Requires GitHub Enterprise Cloud and a token with the read:audit_log scope:
        gh auth refresh -h github.com -s read:audit_log

    The audit log keeps 180 days of events (Git events: 7 days). For long-term retention and
    alerting, configure audit log streaming to a SIEM (e.g. Microsoft Sentinel, Splunk, Azure Event Hubs).

.EXAMPLE
    ./Search-AuditLog.ps1 -ListExamples

.EXAMPLE
    ./Search-AuditLog.ps1 -Org my-org -Phrase 'action:repo.destroy'

.EXAMPLE
    ./Search-AuditLog.ps1 -Enterprise my-enterprise -Phrase 'action:org.update_member created:>=2026-10-01'

.EXAMPLE
    ./Search-AuditLog.ps1 -Org my-org -Phrase 'actor:jdoe' -Include all -Max 50
#>
[CmdletBinding(DefaultParameterSetName = 'Org')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Org')]
    [string]$Org,

    [Parameter(Mandatory, ParameterSetName = 'Enterprise')]
    [string]$Enterprise,

    [Parameter(ParameterSetName = 'Org')]
    [Parameter(ParameterSetName = 'Enterprise')]
    [string]$Phrase = '',

    [Parameter(ParameterSetName = 'Org')]
    [Parameter(ParameterSetName = 'Enterprise')]
    [ValidateSet('web', 'git', 'all')]
    [string]$Include = 'web',

    [Parameter(ParameterSetName = 'Org')]
    [Parameter(ParameterSetName = 'Enterprise')]
    [ValidateRange(1, 100)]
    [int]$Max = 30,

    [Parameter(Mandatory, ParameterSetName = 'Examples')]
    [switch]$ListExamples
)

$ErrorActionPreference = 'Stop'

if ($ListExamples) {
    @(
        [pscustomobject]@{ Phrase = 'action:repo.create';                        Finds = 'Repositories created' }
        [pscustomobject]@{ Phrase = 'action:repo.destroy';                       Finds = 'Repositories deleted' }
        [pscustomobject]@{ Phrase = 'action:repo.access';                        Finds = 'Repository visibility changed (e.g. private -> public)' }
        [pscustomobject]@{ Phrase = 'action:repo.transfer';                      Finds = 'Repositories transferred in/out' }
        [pscustomobject]@{ Phrase = 'action:org.add_member';                     Finds = 'Members added' }
        [pscustomobject]@{ Phrase = 'action:org.remove_member';                  Finds = 'Members removed' }
        [pscustomobject]@{ Phrase = 'action:org.update_member';                  Finds = 'Member role changed (e.g. promoted to owner)' }
        [pscustomobject]@{ Phrase = 'action:org.update_default_repository_permission'; Finds = 'Base permission changed' }
        [pscustomobject]@{ Phrase = 'action:team.add_member';                    Finds = 'Team membership changes' }
        [pscustomobject]@{ Phrase = 'action:protected_branch';                   Finds = 'Classic branch protection changes' }
        [pscustomobject]@{ Phrase = 'action:repository_ruleset';                 Finds = 'Ruleset created / updated / deleted' }
        [pscustomobject]@{ Phrase = 'action:integration_installation';           Finds = 'GitHub Apps installed / removed' }
        [pscustomobject]@{ Phrase = 'action:org.oauth_app_access_approved';      Finds = 'OAuth apps approved for the organization' }
        [pscustomobject]@{ Phrase = 'action:personal_access_token';              Finds = 'Fine-grained PAT requests and approvals' }
        [pscustomobject]@{ Phrase = 'action:secret_scanning_push_protection.bypass'; Finds = 'Someone bypassed secret push protection' }
        [pscustomobject]@{ Phrase = 'action:hook.create';                        Finds = 'Webhooks created' }
        [pscustomobject]@{ Phrase = 'action:copilot';                            Finds = 'Copilot seat and policy changes' }
        [pscustomobject]@{ Phrase = 'actor:USERNAME';                            Finds = 'Everything a specific person did' }
        [pscustomobject]@{ Phrase = 'repo:ORG/REPO';                             Finds = 'Everything that happened to one repository' }
        [pscustomobject]@{ Phrase = 'created:>=2026-10-01';                      Finds = 'Date filter (combine with any of the above)' }
    ) | Format-Table -AutoSize
    return
}

$base = if ($PSCmdlet.ParameterSetName -eq 'Enterprise') { "enterprises/$Enterprise/audit-log" } else { "orgs/$Org/audit-log" }
$path = "$($base)?include=$Include&order=desc&per_page=$Max"
if ($Phrase) { $path += "&phrase=$([uri]::EscapeDataString($Phrase))" }

$out = gh api $path 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Warning ("Audit log query failed: " + ($out -join ' '))
    Write-Warning 'The audit log API needs GitHub Enterprise Cloud, an owner account and the read:audit_log scope:  gh auth refresh -h github.com -s read:audit_log'
    return
}

$events = ConvertFrom-Json -InputObject ($out -join "`n") -NoEnumerate
if ($events.Count -eq 0) { Write-Host 'No matching events.' -ForegroundColor Yellow; return }

$events | ForEach-Object {
    [pscustomobject]@{
        Time    = [DateTimeOffset]::FromUnixTimeMilliseconds([long]$_.'@timestamp').LocalDateTime.ToString('yyyy-MM-dd HH:mm')
        Action  = $_.action
        Actor   = $_.actor
        Target  = (@($_.repo, $_.user, $_.team, $_.org) | Where-Object { $_ } | Select-Object -First 1)
        Country = $_.actor_location.country_code
    }
} | Format-Table -AutoSize
