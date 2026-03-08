<#
.SYNOPSIS
    HubSpot authentication and HTTP helpers.

.DESCRIPTION
    Dot-source this file to gain Connect-HubSpot, Invoke-HubSpotGet,
    Invoke-HubSpotGetPaged, Invoke-HubSpotPost, and Invoke-HubSpotSearch.

    Auth modes
    ----------
    PrivateApp  Uses a HubSpot Private App token (recommended).
                Create one at: Settings > Integrations > Private Apps.
                Set environment.privateAppToken in config.json, or export
                $env:HUBSPOT_TOKEN before running scripts.

    Token hand-off
    --------------
    run-gather.ps1 calls Connect-HubSpot once and stores the token in
    $env:HUBSPOT_TOKEN / $env:HUBSPOT_PORTAL_ID so child processes inherit
    them without re-authenticating.

.NOTES
    Standard HubSpot object type IDs (objectTypeId):
      contacts   0-1    companies  0-2    deals      0-3
      tickets    0-5    products   0-7    line_items 0-8
      quotes     0-14   notes      0-4    tasks      0-27
      calls      0-48   emails     0-49   meetings   0-47
#>

#Requires -Version 7.0

# ── Module-level state ────────────────────────────────────────────────────────
$script:Connection = $null

# ── Well-known standard objects ───────────────────────────────────────────────
$script:StandardObjects = @(
    [PSCustomObject]@{ name = 'contacts';   label = 'Contacts';   objectTypeId = '0-1';  primaryNameProperty = 'firstname' }
    [PSCustomObject]@{ name = 'companies';  label = 'Companies';  objectTypeId = '0-2';  primaryNameProperty = 'name'              }
    [PSCustomObject]@{ name = 'deals';      label = 'Deals';      objectTypeId = '0-3';  primaryNameProperty = 'dealname'          }
    [PSCustomObject]@{ name = 'tickets';    label = 'Tickets';    objectTypeId = '0-5';  primaryNameProperty = 'subject'           }
    [PSCustomObject]@{ name = 'products';   label = 'Products';   objectTypeId = '0-7';  primaryNameProperty = 'name'              }
    [PSCustomObject]@{ name = 'line_items'; label = 'Line Items'; objectTypeId = '0-8';  primaryNameProperty = 'name'              }
    [PSCustomObject]@{ name = 'quotes';     label = 'Quotes';     objectTypeId = '0-14'; primaryNameProperty = 'hs_title'          }
    [PSCustomObject]@{ name = 'notes';      label = 'Notes';      objectTypeId = '0-4';  primaryNameProperty = 'hs_note_body'      }
    [PSCustomObject]@{ name = 'tasks';      label = 'Tasks';      objectTypeId = '0-27'; primaryNameProperty = 'hs_task_subject'   }
    [PSCustomObject]@{ name = 'calls';      label = 'Calls';      objectTypeId = '0-48'; primaryNameProperty = 'hs_call_title'     }
    [PSCustomObject]@{ name = 'emails';     label = 'Emails';     objectTypeId = '0-49'; primaryNameProperty = 'hs_email_subject'  }
    [PSCustomObject]@{ name = 'meetings';   label = 'Meetings';   objectTypeId = '0-47'; primaryNameProperty = 'hs_meeting_title'  }
)

# ── Standard associations (from → to, label, cardinality) ────────────────────
# Cardinality: ManyToMany or OneToMany (deals→line_items, deals→quotes are O2M)
$script:StandardAssociations = @(
    [PSCustomObject]@{ fromObject = 'contacts';   toObject = 'companies';  cardinality = 'ManyToMany'; label = 'company'     }
    [PSCustomObject]@{ fromObject = 'contacts';   toObject = 'deals';      cardinality = 'ManyToMany'; label = 'deal'        }
    [PSCustomObject]@{ fromObject = 'contacts';   toObject = 'tickets';    cardinality = 'ManyToMany'; label = 'ticket'      }
    [PSCustomObject]@{ fromObject = 'contacts';   toObject = 'calls';      cardinality = 'ManyToMany'; label = 'call'        }
    [PSCustomObject]@{ fromObject = 'contacts';   toObject = 'emails';     cardinality = 'ManyToMany'; label = 'email'       }
    [PSCustomObject]@{ fromObject = 'contacts';   toObject = 'meetings';   cardinality = 'ManyToMany'; label = 'meeting'     }
    [PSCustomObject]@{ fromObject = 'contacts';   toObject = 'notes';      cardinality = 'ManyToMany'; label = 'note'        }
    [PSCustomObject]@{ fromObject = 'contacts';   toObject = 'tasks';      cardinality = 'ManyToMany'; label = 'task'        }
    [PSCustomObject]@{ fromObject = 'companies';  toObject = 'deals';      cardinality = 'ManyToMany'; label = 'deal'        }
    [PSCustomObject]@{ fromObject = 'companies';  toObject = 'tickets';    cardinality = 'ManyToMany'; label = 'ticket'      }
    [PSCustomObject]@{ fromObject = 'companies';  toObject = 'calls';      cardinality = 'ManyToMany'; label = 'call'        }
    [PSCustomObject]@{ fromObject = 'companies';  toObject = 'meetings';   cardinality = 'ManyToMany'; label = 'meeting'     }
    [PSCustomObject]@{ fromObject = 'companies';  toObject = 'notes';      cardinality = 'ManyToMany'; label = 'note'        }
    [PSCustomObject]@{ fromObject = 'companies';  toObject = 'tasks';      cardinality = 'ManyToMany'; label = 'task'        }
    [PSCustomObject]@{ fromObject = 'deals';      toObject = 'line_items'; cardinality = 'OneToMany';  label = 'line item'   }
    [PSCustomObject]@{ fromObject = 'deals';      toObject = 'quotes';     cardinality = 'OneToMany';  label = 'quote'       }
    [PSCustomObject]@{ fromObject = 'deals';      toObject = 'tickets';    cardinality = 'ManyToMany'; label = 'ticket'      }
    [PSCustomObject]@{ fromObject = 'deals';      toObject = 'calls';      cardinality = 'ManyToMany'; label = 'call'        }
    [PSCustomObject]@{ fromObject = 'deals';      toObject = 'meetings';   cardinality = 'ManyToMany'; label = 'meeting'     }
    [PSCustomObject]@{ fromObject = 'deals';      toObject = 'notes';      cardinality = 'ManyToMany'; label = 'note'        }
    [PSCustomObject]@{ fromObject = 'deals';      toObject = 'tasks';      cardinality = 'ManyToMany'; label = 'task'        }
    [PSCustomObject]@{ fromObject = 'tickets';    toObject = 'calls';      cardinality = 'ManyToMany'; label = 'call'        }
    [PSCustomObject]@{ fromObject = 'tickets';    toObject = 'meetings';   cardinality = 'ManyToMany'; label = 'meeting'     }
    [PSCustomObject]@{ fromObject = 'tickets';    toObject = 'notes';      cardinality = 'ManyToMany'; label = 'note'        }
    [PSCustomObject]@{ fromObject = 'tickets';    toObject = 'tasks';      cardinality = 'ManyToMany'; label = 'task'        }
    [PSCustomObject]@{ fromObject = 'line_items'; toObject = 'products';   cardinality = 'ManyToMany'; label = 'product'     }
)

# ── Public: authenticate and populate $script:Connection ─────────────────────
function Connect-HubSpot {
    <#
    .SYNOPSIS Authenticates to HubSpot and caches credentials for this session.
    #>
    param(
        [string]$ConfigPath = "$PSScriptRoot/config.json"
    )

    # Allow child-process token hand-off from run-gather.ps1
    if ($env:HUBSPOT_TOKEN) {
        $script:Connection = @{
            Token    = $env:HUBSPOT_TOKEN
            BaseUrl  = 'https://api.hubapi.com'
            PortalId = $env:HUBSPOT_PORTAL_ID ?? ''
        }
        Write-Host "Using inherited HubSpot token (portal: $($script:Connection.PortalId))" -ForegroundColor DarkGray
        return
    }

    $config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
    $token  = $config.environment.privateAppToken

    if (-not $token) {
        Write-Error "No HubSpot Private App token found.`nSet environment.privateAppToken in config.json, or export `$env:HUBSPOT_TOKEN."
        exit 1
    }

    $script:Connection = @{
        Token    = $token
        BaseUrl  = 'https://api.hubapi.com'
        PortalId = $config.environment.portalId ?? ''
    }

    # Export for child processes
    $env:HUBSPOT_TOKEN    = $token
    $env:HUBSPOT_PORTAL_ID = $script:Connection.PortalId

    Write-Host "Connected to HubSpot portal $($script:Connection.PortalId)" -ForegroundColor Green
}

# ── Internal: build auth headers ──────────────────────────────────────────────
function Get-HsHeaders {
    if (-not $script:Connection) { Connect-HubSpot }
    return @{
        Authorization  = "Bearer $($script:Connection.Token)"
        Accept         = 'application/json'
        'Content-Type' = 'application/json'
    }
}

# ── Public: single GET against HubSpot API ────────────────────────────────────
function Invoke-HubSpotGet {
    <#
    .SYNOPSIS Issues a GET request against the HubSpot API. No pagination.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )
    $headers = Get-HsHeaders
    $url     = "$($script:Connection.BaseUrl)$Path"
    return Invoke-RestMethod -Uri $url -Headers $headers -Method Get
}

# ── Public: paginated GET following after-cursor pagination ───────────────────
function Invoke-HubSpotGetPaged {
    <#
    .SYNOPSIS
        Issues a GET request and follows HubSpot after-cursor pagination,
        returning the combined results array.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$ResultsProperty = 'results',
        [int]$PageSize = 100
    )
    $headers = Get-HsHeaders
    $all     = [System.Collections.Generic.List[object]]::new()
    $sep     = if ($Path -match '\?') { '&' } else { '?' }
    $url     = "$($script:Connection.BaseUrl)$Path${sep}limit=$PageSize"

    do {
        $resp  = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        $items = $resp.$ResultsProperty
        if ($items) { $all.AddRange([object[]]$items) }

        $after = $resp.paging?.next?.after
        $url   = if ($after) {
            "$($script:Connection.BaseUrl)$Path${sep}limit=$PageSize&after=$after"
        } else { $null }
    } while ($url)

    return $all.ToArray()
}

# ── Public: POST (used for search) ────────────────────────────────────────────
function Invoke-HubSpotPost {
    <#
    .SYNOPSIS Issues a POST request against the HubSpot API.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        $Body
    )
    $headers = Get-HsHeaders
    $url     = "$($script:Connection.BaseUrl)$Path"
    $json    = $Body | ConvertTo-Json -Depth 10 -Compress
    return Invoke-RestMethod -Uri $url -Headers $headers -Method Post -Body $json
}

# ── Public: CRM search (returns total + results) ──────────────────────────────
function Invoke-HubSpotSearch {
    <#
    .SYNOPSIS
        Issues a CRM search request. Returns the full response (includes .total).
        Use limit=1 and read .total for a count-only query.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ObjectType,

        $FilterGroups = @(),
        [string[]]$Properties = @('hs_object_id'),
        [int]$Limit = 1
    )
    $body = @{
        filterGroups = $FilterGroups
        sorts        = @()
        properties   = $Properties
        limit        = $Limit
    }
    return Invoke-HubSpotPost "/crm/v3/objects/$ObjectType/search" $body
}
