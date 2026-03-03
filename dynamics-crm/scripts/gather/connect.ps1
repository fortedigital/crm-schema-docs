<#
.SYNOPSIS
    Dataverse authentication and HTTP helpers.

.DESCRIPTION
    Dot-source this file to gain Connect-Dataverse and Invoke-DataverseGet.

    Auth modes
    ----------
    Interactive     Device-code flow. Opens a browser prompt once per session.
                    Uses the well-known Power Apps public client ID by default.
                    Set tenantId to "common" if your tenant is unknown.

    ServicePrincipal  Client-credentials flow. Requires an Azure AD app registration
                      with the Dataverse user_impersonation permission granted.
                      Pass the client secret via the DATAVERSE_CLIENT_SECRET env var
                      (never hard-code it).

    Token hand-off
    --------------
    run-gather.ps1 calls Connect-Dataverse once and the resulting token is stored in
    $env:DATAVERSE_TOKEN / $env:DATAVERSE_URL so child processes (get-*.ps1 scripts
    invoked via pwsh -File) inherit them without re-authenticating.
#>

#Requires -Version 7.0

# ── Module-level state ────────────────────────────────────────────────────────
$script:Connection = $null

# ── Public: authenticate and populate $script:Connection ─────────────────────
function Connect-Dataverse {
    <#
    .SYNOPSIS Authenticates to Dataverse and caches the token for this session.
    #>
    param(
        [string]$ConfigPath = "$PSScriptRoot/config.json"
    )

    # Allow child-process token hand-off from run-gather.ps1
    if ($env:DATAVERSE_TOKEN -and $env:DATAVERSE_URL) {
        $script:Connection = @{
            EnvironmentUrl = $env:DATAVERSE_URL
            Token          = $env:DATAVERSE_TOKEN
        }
        Write-Host "Using inherited token for $($script:Connection.EnvironmentUrl)" -ForegroundColor DarkGray
        return
    }

    $config  = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $env_cfg = $config.environment
    $baseUrl = $env_cfg.url.TrimEnd('/')
    $tenantId = if ($env_cfg.tenantId -and $env_cfg.tenantId -ne '<tenant-id>') {
        $env_cfg.tenantId
    } else {
        'common'
    }

    $tokenEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"
    $scope         = "$baseUrl/.default"

    if ($env_cfg.authMode -eq 'ServicePrincipal') {
        $clientSecret = $env:DATAVERSE_CLIENT_SECRET
        if (-not $clientSecret) {
            $clientSecret = Read-Host "Client secret for $($env_cfg.clientId)" -AsSecureString |
                            ConvertFrom-SecureString -AsPlainText
        }
        $body = @{
            grant_type    = 'client_credentials'
            client_id     = $env_cfg.clientId
            client_secret = $clientSecret
            scope         = $scope
        }
        $resp = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body
    }
    else {
        # Device-code (interactive)
        $deviceResp = Invoke-RestMethod -Method Post `
            -Uri "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/devicecode" `
            -Body @{ client_id = $env_cfg.clientId; scope = $scope }

        Write-Host "`n$($deviceResp.message)`n" -ForegroundColor Cyan

        $pollBody = @{
            grant_type  = 'urn:ietf:params:oauth2:grant-type:device_code'
            client_id   = $env_cfg.clientId
            device_code = $deviceResp.device_code
        }
        $interval = [int]($deviceResp.interval ?? 5)

        $resp = $null
        do {
            Start-Sleep -Seconds $interval
            try {
                $resp = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $pollBody -ErrorAction Stop
            } catch {
                $err = ($_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue).error
                if ($err -ne 'authorization_pending') { throw }
            }
        } while (-not $resp)
    }

    $script:Connection = @{
        EnvironmentUrl = $baseUrl
        Token          = $resp.access_token
        ExpiresAt      = (Get-Date).AddSeconds([int]$resp.expires_in - 30)
    }

    # Export for child processes
    $env:DATAVERSE_TOKEN = $resp.access_token
    $env:DATAVERSE_URL   = $baseUrl

    Write-Host "Connected to $baseUrl" -ForegroundColor Green
}

# ── Public: paginated GET against the Dataverse Web API ──────────────────────
function Invoke-DataverseGet {
    <#
    .SYNOPSIS
        Issues a GET request against the Dataverse Web API, following all
        @odata.nextLink pages. Returns the combined value array.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RelativeUrl
    )

    if (-not $script:Connection) { Connect-Dataverse }

    $headers = @{
        Authorization      = "Bearer $($script:Connection.Token)"
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        Accept             = 'application/json'
        Prefer             = 'odata.include-annotations="*"'
    }

    $url     = "$($script:Connection.EnvironmentUrl)/api/data/v9.2/$RelativeUrl"
    $results = [System.Collections.Generic.List[object]]::new()

    do {
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        if ($resp.value) { $results.AddRange([object[]]$resp.value) }
        $url = $resp.'@odata.nextLink'
    } while ($url)

    return $results.ToArray()
}
