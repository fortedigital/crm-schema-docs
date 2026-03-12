<#
.SYNOPSIS
    Salesforce authentication and HTTP helpers.

.DESCRIPTION
    Dot-source this file to gain Select-SalesforceOrg, Connect-Salesforce,
    Invoke-SalesforceGet, and Invoke-SalesforceToolingQuery.

    Auth modes
    ----------
    Interactive     Opens a browser via 'sf org login web'. Uses the org alias
                    from config.json. Authenticates once; subsequent runs reuse
                    the cached session managed by the sf CLI.

    JWT             Non-interactive server-to-server auth via 'sf org login jwt'.
                    Requires a Connected App with a certificate and:
                      environment.clientId   — Connected App consumer key
                      environment.username   — Salesforce username
                      environment.jwtKeyFile — path to the private key file

    Token hand-off
    --------------
    run-gather.ps1 calls Connect-Salesforce once and the resulting token is stored
    in $env:SF_TOKEN / $env:SF_INSTANCE_URL so child processes (get-*.ps1 scripts
    invoked via pwsh -File) inherit them without re-authenticating.
#>

#Requires -Version 7.0

# ── Module-level state ────────────────────────────────────────────────────────
$script:Connection = $null

# ── Public: org picker using sf CLI ──────────────────────────────────────────
function Select-SalesforceOrg {
    <#
    .SYNOPSIS Lists authenticated orgs via the Salesforce CLI and updates config.json.
    #>
    param(
        [string]$ConfigPath = "$PSScriptRoot/config.json"
    )

    if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
        Write-Warning "sf CLI not found. Install: npm install --global @salesforce/cli"
        Write-Warning "Skipping org selection — set environment.orgAlias in config.json manually."
        return
    }

    Write-Host "Fetching authenticated orgs from Salesforce CLI..." -ForegroundColor Cyan
    $raw = sf org list --json 2>$null
    if (-not $raw) {
        Write-Warning "sf returned no orgs. Run 'sf org login web' first."
        return
    }

    $parsed = $raw | ConvertFrom-Json
    $orgs   = @($parsed.result.nonScratchOrgs) + @($parsed.result.sandboxes ?? @())
    $orgs   = $orgs | Where-Object { $_ }

    if ($orgs.Count -eq 0) {
        Write-Warning "No authenticated orgs found. Run 'sf org login web' first."
        return
    }

    Write-Host ""
    for ($i = 0; $i -lt $orgs.Count; $i++) {
        $o     = $orgs[$i]
        $alias = $o.alias       ?? '(no alias)'
        $user  = $o.username    ?? '(unknown user)'
        $url   = $o.instanceUrl ?? '(unknown url)'
        $def   = if ($o.isDefaultOrg) { ' [default]' } else { '' }
        Write-Host "  [$i] $alias$def"
        Write-Host "      $user  $url" -ForegroundColor DarkGray
    }
    Write-Host ""

    [int]$idx = Read-Host "Select org (0-$($orgs.Count - 1))"
    $selected = $orgs[$idx]
    $alias    = $selected.alias ?? $selected.username

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $config.environment.orgAlias = $alias
    $config | ConvertTo-Json -Depth 5 | Set-Content $ConfigPath -Encoding UTF8

    Write-Host "Config updated → alias '$alias'" -ForegroundColor Green
    return $alias
}

# ── Public: authenticate and populate $script:Connection ─────────────────────
function Connect-Salesforce {
    <#
    .SYNOPSIS Authenticates to Salesforce and caches the token for this session.
    #>
    param(
        [string]$ConfigPath = "$PSScriptRoot/config.json"
    )

    # Allow child-process token hand-off from run-gather.ps1
    if ($env:SF_TOKEN -and $env:SF_INSTANCE_URL) {
        $script:Connection = @{
            InstanceUrl = $env:SF_INSTANCE_URL
            Token       = $env:SF_TOKEN
            ApiVersion  = $env:SF_API_VERSION ?? '62.0'
        }
        Write-Host "Using inherited token for $($script:Connection.InstanceUrl)" -ForegroundColor DarkGray
        return
    }

    if (-not (Get-Command sf -ErrorAction SilentlyContinue)) {
        Write-Error "sf CLI is required. Install: npm install --global @salesforce/cli"
        exit 1
    }

    $config   = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $env_cfg  = $config.environment
    $alias    = $env_cfg.orgAlias
    $version  = $env_cfg.apiVersion ?? '62.0'

    if ($env_cfg.authMode -eq 'JWT') {
        # Non-interactive JWT flow
        $jwtArgs = @(
            'org', 'login', 'jwt'
            '--username',     $env_cfg.username
            '--client-id',    $env_cfg.clientId
            '--jwt-key-file', $env_cfg.jwtKeyFile
            '--alias',        $alias
            '--json'
        )
        $result = sf @jwtArgs 2>$null | ConvertFrom-Json
        if ($result.status -ne 0) {
            Write-Error "JWT login failed: $($result.message)"
            exit 1
        }
        Write-Host "JWT login successful → $alias" -ForegroundColor Green
    }
    else {
        # Interactive browser flow — authenticates if not already cached
        $loginArgs = @('org', 'login', 'web', '--alias', $alias, '--json')
        Write-Host "Opening browser for Salesforce login (alias: $alias)..." -ForegroundColor Cyan
        $result = sf @loginArgs 2>$null | ConvertFrom-Json
        if ($result.status -ne 0) {
            Write-Warning "sf org login web returned status $($result.status) — org may already be authenticated."
        }
    }

    # Retrieve the cached access token for this org
    $displayRaw = sf org display --target-org $alias --json 2>$null
    if (-not $displayRaw) {
        Write-Error "Could not retrieve org info for alias '$alias'. Run 'sf org login web --alias $alias' first."
        exit 1
    }

    $display = $displayRaw | ConvertFrom-Json
    if ($display.status -ne 0) {
        Write-Error "sf org display failed: $($display.message)"
        exit 1
    }

    $res = $display.result
    $script:Connection = @{
        InstanceUrl = $res.instanceUrl.TrimEnd('/')
        Token       = $res.accessToken
        ApiVersion  = $version
    }

    # Export for child processes
    $env:SF_TOKEN        = $res.accessToken
    $env:SF_INSTANCE_URL = $res.instanceUrl.TrimEnd('/')
    $env:SF_API_VERSION  = $version

    Write-Host "Connected to $($script:Connection.InstanceUrl)" -ForegroundColor Green
}

# ── Internal: build auth headers ──────────────────────────────────────────────
function Get-SfHeaders {
    if (-not $script:Connection) { Connect-Salesforce }
    return @{
        Authorization  = "Bearer $($script:Connection.Token)"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }
}

# ── Public: single GET against Salesforce REST API ────────────────────────────
function Invoke-SalesforceGet {
    <#
    .SYNOPSIS
        Issues a GET request against the Salesforce REST API.
        Returns the raw response object. No automatic pagination.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $headers = Get-SfHeaders
    $url     = "$($script:Connection.InstanceUrl)/services/data/v$($script:Connection.ApiVersion)/$Path"
    return Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}

# ── Public: paginated Tooling API SOQL query ──────────────────────────────────
function Invoke-SalesforceToolingQuery {
    <#
    .SYNOPSIS
        Issues a SOQL query against the Salesforce Tooling API, following
        all nextRecordsUrl pages. Returns the combined records array.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Query
    )

    $headers  = Get-SfHeaders
    $encoded  = [System.Uri]::EscapeDataString($Query)
    $url      = "$($script:Connection.InstanceUrl)/services/data/v$($script:Connection.ApiVersion)/tooling/query?q=$encoded"
    $results  = [System.Collections.Generic.List[object]]::new()

    do {
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        if ($resp.records) { $results.AddRange([object[]]$resp.records) }
        $url = if (-not $resp.done -and $resp.nextRecordsUrl) {
            "$($script:Connection.InstanceUrl)$($resp.nextRecordsUrl)"
        } else {
            $null
        }
    } while ($url)

    return $results.ToArray()
}
