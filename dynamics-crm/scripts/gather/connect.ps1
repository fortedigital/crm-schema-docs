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
        Write-Host "POST $tokenEndpoint" -ForegroundColor Yellow
        Write-Host "Body: $($body | ConvertTo-Json -Compress)" -ForegroundColor Yellow
        $resp = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body
    }
    else {
        # Authorization-code + PKCE (interactive)
        $redirectPort = 8400
        $redirectUri  = "http://localhost:$redirectPort"

        # Generate PKCE code verifier + challenge
        $verifierBytes = [byte[]]::new(32)
        [System.Security.Cryptography.RandomNumberGenerator]::Fill($verifierBytes)
        $codeVerifier  = [Convert]::ToBase64String($verifierBytes) -replace '\+','-' -replace '/','_' -replace '='
        $challengeHash = [System.Security.Cryptography.SHA256]::HashData(
            [System.Text.Encoding]::ASCII.GetBytes($codeVerifier))
        $codeChallenge = [Convert]::ToBase64String($challengeHash) -replace '\+','-' -replace '/','_' -replace '='

        $state = [guid]::NewGuid().ToString('N')

        $authParams = @(
            "client_id=$($env_cfg.clientId)"
            "response_type=code"
            "redirect_uri=$([uri]::EscapeDataString($redirectUri))"
            "scope=$([uri]::EscapeDataString($scope + ' offline_access openid'))"
            "state=$state"
            "code_challenge=$codeChallenge"
            "code_challenge_method=S256"
        )
        if ($env_cfg.loginHint) {
            $authParams += "login_hint=$([uri]::EscapeDataString($env_cfg.loginHint))"
        }
        $authUrl = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize?" + ($authParams -join '&')

        # Start a one-shot HTTP listener to capture the redirect
        $listener = [System.Net.HttpListener]::new()
        $listener.Prefixes.Add("$redirectUri/")
        $listener.Start()

        Write-Host "Opening browser for sign-in…" -ForegroundColor Cyan
        Write-Host "GET $authUrl" -ForegroundColor Yellow

        # Open browser (cross-platform)
        if     ($IsWindows) { Start-Process $authUrl }
        elseif ($IsMacOS)   { Start-Process 'open' -ArgumentList $authUrl }
        else                { Start-Process 'xdg-open' -ArgumentList $authUrl }

        Write-Host "Waiting for authentication redirect on $redirectUri …" -ForegroundColor DarkGray
        $ctx = $listener.GetContext()          # blocks until the browser redirects

        # Send a friendly page back to the browser, then close the listener
        $html = [System.Text.Encoding]::UTF8.GetBytes(
            '<html><body><h3>Authentication complete — you can close this tab.</h3></body></html>')
        $ctx.Response.ContentType = 'text/html'
        $ctx.Response.OutputStream.Write($html, 0, $html.Length)
        $ctx.Response.Close()
        $listener.Stop()

        # Parse the authorization code from the query string
        $qs = [System.Web.HttpUtility]::ParseQueryString($ctx.Request.Url.Query)
        if ($qs['error']) {
            throw "Authorization failed: $($qs['error']) — $($qs['error_description'])"
        }
        if ($qs['state'] -ne $state) {
            throw "State mismatch — possible CSRF. Expected $state, got $($qs['state'])"
        }
        $authCode = $qs['code']

        # Exchange the code for tokens
        $body = @{
            grant_type    = 'authorization_code'
            client_id     = $env_cfg.clientId
            code          = $authCode
            redirect_uri  = $redirectUri
            code_verifier = $codeVerifier
            scope         = $scope
        }
        Write-Host "POST $tokenEndpoint" -ForegroundColor Yellow
        Write-Host "Body: $($body | ConvertTo-Json -Compress)" -ForegroundColor Yellow
        $resp = Invoke-RestMethod -Method Post -Uri $tokenEndpoint -Body $body
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

# ── Public: validate that the current token is usable ────────────────────────
function Test-DataverseAuth {
    <#
    .SYNOPSIS
        Calls WhoAmI to verify the token is valid. Returns $true on success, $false on failure.
    #>
    if (-not $script:Connection -or -not $script:Connection.Token) {
        Write-Warning "No Dataverse token available."
        return $false
    }
    try {
        $headers = @{
            Authorization      = "Bearer $($script:Connection.Token)"
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
            Accept             = 'application/json'
        }
        $url = "$($script:Connection.EnvironmentUrl)/api/data/v9.2/WhoAmI"
        $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        Write-Host "Token valid — UserId: $($resp.UserId)" -ForegroundColor Green
        return $true
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        Write-Warning "Token validation failed (HTTP $statusCode): $($_.Exception.Message)"
        return $false
    }
}

# ── Auth-failure exit code (used by run-gather.ps1 to detect 401s) ───────────
$script:AuthFailureExitCode = 91

# ── Public: validate + prompt to reauthenticate if token is invalid ──────────
function Confirm-DataverseAuth {
    <#
    .SYNOPSIS
        Tests the current token. If invalid, prompts the user to reauthenticate.
        Returns $true if auth is valid (or was refreshed), exits on decline.
    #>
    param(
        [string]$ConfigPath = "$PSScriptRoot/config.json"
    )

    if (Test-DataverseAuth) { return $true }

    Write-Host "`nAuthentication is invalid or expired." -ForegroundColor Red
    $retry = Read-Host "Do you want to reauthenticate? (y/N)"
    if ($retry -match '^[Yy]') {
        # Clear stale token
        $script:Connection = $null
        Remove-Item Env:DATAVERSE_TOKEN -ErrorAction SilentlyContinue
        Remove-Item Env:DATAVERSE_URL   -ErrorAction SilentlyContinue
        Connect-Dataverse -ConfigPath $ConfigPath
        if (Test-DataverseAuth) {
            return $true
        }
        Write-Error "Reauthentication failed."
        exit $script:AuthFailureExitCode
    } else {
        Write-Host "Aborting." -ForegroundColor Yellow
        exit $script:AuthFailureExitCode
    }
}

# ── Public: paginated GET against the Dataverse Web API ──────────────────────
function Invoke-DataverseGet {
    <#
    .SYNOPSIS
        Issues a GET request against the Dataverse Web API, following all
        @odata.nextLink pages. Returns the combined value array.
        Exits with code 91 on HTTP 401 (Unauthorized) so the caller can
        detect auth failures and prompt for reauthentication.
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
        Write-Host "GET $url" -ForegroundColor Yellow
        try {
            $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 401) {
                Write-Error "HTTP 401 Unauthorized — token is invalid or expired."
                exit $script:AuthFailureExitCode
            }
            throw
        }
        if ($null -ne $resp.value) {
            $results.AddRange([object[]]$resp.value)
        } elseif ($results.Count -eq 0) {
            # Non-collection response (e.g. WhoAmI, single-entity lookup)
            return $resp
        }
        $url = $resp.'@odata.nextLink'
    } while ($url)

    return $results.ToArray()
}
