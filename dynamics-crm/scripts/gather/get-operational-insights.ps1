<#
.SYNOPSIS
    Gathers operational insights for each entity — row counts, activity,
    data quality signals, relationship cardinalities, duplicates,
    transformation rules, and integration touchpoints.

.DESCRIPTION
    For every entity in data/raw/entities.json this script collects:

      • Row counts and data volumes (total records, statecode breakdown)
      • Actual relationship cardinalities (sampled FK distributions)
      • Data quality problems (null primary name, null key fields)
      • Duplicate rates (records sharing the same primary name value)
      • Active-use vs legacy indicators (recent creates/modifies, statecode)
      • Transformation rules (plugins, workflows, business rules on the entity)
      • Integration touchpoints (async jobs, plugin steps, data sync)

    Depends on get-entities.ps1 having run first (needs entities.json).

.OUTPUTS
    data/raw/operational-insights/<entity>.json — one file per entity
    data/raw/operational-insights/_global.json  — org-wide integration summary

.PARAMETER ConfigPath
    Path to config.json. Defaults to the config.json next to this script.

.PARAMETER Entity
    Optional. Run for a single entity logical name only (e.g. 'account').
    Useful for testing before running against all entities.

.PARAMETER Refresh
    Force re-fetch of all entities, even if output files already exist.
    Without this switch, entities with existing output files are skipped (resume mode).

.EXAMPLE
    .\get-operational-insights.ps1 -Entity account

.EXAMPLE
    # Force re-fetch of all entities
    .\get-operational-insights.ps1 -Refresh
#>

#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = "$PSScriptRoot/config.json",
    [string]$Entity,
    [switch]$Refresh
)

. "$PSScriptRoot/connect.ps1"

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rawDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $config.output.rawDir))
$outDir = Join-Path $rawDir 'operational-insights'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null

# ── Load entity definitions ──────────────────────────────────────────────────
$entitiesFile = Join-Path $rawDir 'entities.json'
if (-not (Test-Path $entitiesFile)) {
    Write-Error "entities.json not found at $entitiesFile. Run get-entities.ps1 first."
    exit 1
}
$entityDefs = Get-Content $entitiesFile -Raw | ConvertFrom-Json

if ($Entity) {
    $entityDefs = $entityDefs | Where-Object { ($_.LogicalName ?? $_.logicalName) -eq $Entity }
    if ($entityDefs.Count -eq 0) {
        Write-Error "Entity '$Entity' not found in entities.json."
        exit 1
    }
    # Ensure it's still an array
    $entityDefs = @($entityDefs)
    Write-Host "Filtered to single entity: $Entity" -ForegroundColor Cyan
}

# When running standalone (not from run-gather.ps1), clear any stale inherited token
# so Connect-Dataverse does a fresh interactive auth
if (($Entity -or -not $Refresh) -and $env:DATAVERSE_TOKEN) {
    Write-Host "Clearing stale inherited token — will re-authenticate" -ForegroundColor DarkGray
    Remove-Item Env:DATAVERSE_TOKEN -ErrorAction SilentlyContinue
    Remove-Item Env:DATAVERSE_URL   -ErrorAction SilentlyContinue
}

if (-not $Refresh) {
    $before = $entityDefs.Count
    $entityDefs = @($entityDefs | Where-Object {
        $name = $_.LogicalName ?? $_.logicalName
        -not (Test-Path (Join-Path $outDir "$name.json"))
    })
    $skipped = $before - $entityDefs.Count
    Write-Host "Resume mode (default): skipping $skipped already-fetched entities, $($entityDefs.Count) remaining" -ForegroundColor Cyan
    if ($entityDefs.Count -eq 0) {
        Write-Host "All entities already fetched. Use -Refresh to force re-fetch." -ForegroundColor Green
        exit 0
    }
}

Connect-Dataverse -ConfigPath $ConfigPath

# ── Helper: safe count query ─────────────────────────────────────────────────
function Get-EntityCount {
    param([string]$EntitySetName, [string]$Filter)
    try {
        $headers = @{
            Authorization      = "Bearer $($script:Connection.Token)"
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        if ($Filter) {
            # Filtered: /$count path does not support $filter — use $count=true on collection
            $url = "${EntitySetName}?`$filter=$Filter&`$count=true"
            $headers['Accept'] = 'application/json'
            $headers['Prefer'] = 'odata.maxpagesize=1'
            $fullUrl = "$($script:Connection.EnvironmentUrl)/api/data/v9.2/$url"
            Write-Host "  [count] GET $fullUrl" -ForegroundColor DarkGray
            $resp = Invoke-RestMethod -Uri $fullUrl -Headers $headers -Method Get
            $count = $resp.'@odata.count'
            Write-Host "  [count] → $count" -ForegroundColor DarkGray
            return $count
        } else {
            # Unfiltered: /$count path returns a plain integer
            $url = "${EntitySetName}/`$count"
            $headers['Accept'] = 'text/plain'
            $headers['ConsistencyLevel'] = 'eventual'
            $fullUrl = "$($script:Connection.EnvironmentUrl)/api/data/v9.2/$url"
            Write-Host "  [count] GET $fullUrl" -ForegroundColor DarkGray
            $resp = Invoke-RestMethod -Uri $fullUrl -Headers $headers -Method Get
            # Response may contain BOM or invisible chars — extract digits only
            $digits = [regex]::Match("$resp", '\d+').Value
            $count = [int]$digits
            Write-Host "  [count] → $count" -ForegroundColor DarkGray
            return $count
        }
    } catch {
        Write-Host "  [count] FAILED: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            try {
                $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $body = $reader.ReadToEnd()
                Write-Host "  [count] Response: $($body.Substring(0, [Math]::Min(500, $body.Length)))" -ForegroundColor Red
            } catch { }
        }
        return $null
    }
}

# ── Helper: safe limited query ───────────────────────────────────────────────
function Get-EntitySample {
    param([string]$Url)
    try {
        Write-Host "  [query] $Url" -ForegroundColor DarkGray
        $result = Invoke-DataverseGet -RelativeUrl $Url
        $n = if ($result -is [array]) { $result.Count } else { 1 }
        Write-Host "  [query] → $n results" -ForegroundColor DarkGray
        return $result
    } catch {
        Write-Host "  [query] FAILED: $($_.Exception.Message)" -ForegroundColor Red
        if ($_.Exception.Response) {
            try {
                $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
                $body = $reader.ReadToEnd()
                Write-Host "  [query] Response: $($body.Substring(0, [Math]::Min(500, $body.Length)))" -ForegroundColor Red
            } catch { }
        }
        return $null
    }
}

# ── 1. Global integration summary (org-wide, run once) ──────────────────────
Write-Host "`n--- Global integration summary ---" -ForegroundColor Yellow

$globalIntegrations = [ordered]@{}

# SDK Message Processing Steps (plugins & custom actions)
$pluginSteps = Get-EntitySample "sdkmessageprocessingsteps?`$select=name,sdkmessageprocessingstepid,stage,mode,statecode,_sdkmessagefilterid_value,_plugintypeid_value&`$filter=ishidden/Value eq false&`$top=5000"
$globalIntegrations['pluginStepCount'] = if ($pluginSteps) { $pluginSteps.Count } else { 0 }
$globalIntegrations['pluginStepsByState'] = @{
    active   = ($pluginSteps | Where-Object { $_.statecode -eq 0 }).Count
    inactive = ($pluginSteps | Where-Object { $_.statecode -ne 0 }).Count
}

# Workflows / Business Rules / Flows
$workflows = Get-EntitySample "workflows?`$select=name,category,statecode,primaryentity,type&`$filter=componentstate eq 0&`$top=5000"
$globalIntegrations['workflowCount'] = if ($workflows) { $workflows.Count } else { 0 }
# category: 0=Workflow, 1=Dialog, 2=BusinessRule, 3=Action, 4=BusinessProcessFlow, 5=ModernFlow, 6=DesktopFlow
$wfByCategory = @{}
foreach ($wf in $workflows) {
    $cat = switch ($wf.category) {
        0 { 'Workflow' }
        1 { 'Dialog' }
        2 { 'BusinessRule' }
        3 { 'Action' }
        4 { 'BusinessProcessFlow' }
        5 { 'PowerAutomateFlow' }
        6 { 'DesktopFlow' }
        default { "Other_$($wf.category)" }
    }
    $wfByCategory[$cat] = ($wfByCategory[$cat] ?? 0) + 1
}
$globalIntegrations['workflowsByCategory'] = $wfByCategory

# Data sync profiles / integration entities
$syncProfiles = Get-EntitySample "datasyncstates?`$select=name,entityname&`$top=500"
$globalIntegrations['dataSyncProfileCount'] = if ($syncProfiles) { $syncProfiles.Count } else { 0 }

# Connection roles (integration endpoints)
$connectionRoles = Get-EntitySample "connectionroles?`$select=name,statecode,category&`$top=500"
$globalIntegrations['connectionRoleCount'] = if ($connectionRoles) { $connectionRoles.Count } else { 0 }

$globalFile = Join-Path $outDir '_global.json'
$globalIntegrations | ConvertTo-Json -Depth 5 | Set-Content $globalFile -Encoding UTF8
Write-Host "Global integration summary → $globalFile" -ForegroundColor Green

# ── 2. Per-entity operational insights ───────────────────────────────────────
$total   = $entityDefs.Count
$current = 0

# Build lookup: entity → plugin steps
$pluginsByEntity = @{}
if ($pluginSteps) {
    # Resolve filter entity names from SDK message filters
    $filters = Get-EntitySample "sdkmessagefilters?`$select=sdkmessagefilterid,primaryobjecttypecode&`$top=5000"
    $filterMap = @{}
    if ($filters) {
        foreach ($f in $filters) {
            $filterMap[$f.sdkmessagefilterid] = $f.primaryobjecttypecode
        }
    }
    foreach ($step in $pluginSteps) {
        $filterId = $step.'_sdkmessagefilterid_value'
        $entityName = if ($filterId -and $filterMap.ContainsKey($filterId)) { $filterMap[$filterId] } else { 'none' }
        if (-not $pluginsByEntity[$entityName]) { $pluginsByEntity[$entityName] = [System.Collections.Generic.List[object]]::new() }
        $pluginsByEntity[$entityName].Add($step)
    }
}

# Build lookup: entity → workflows
$workflowsByEntity = @{}
if ($workflows) {
    foreach ($wf in $workflows) {
        $entityName = $wf.primaryentity
        if ($entityName -and $entityName -ne 'none') {
            if (-not $workflowsByEntity[$entityName]) { $workflowsByEntity[$entityName] = [System.Collections.Generic.List[object]]::new() }
            $workflowsByEntity[$entityName].Add($wf)
        }
    }
}

# Date thresholds for activity analysis
$now       = Get-Date
$days30    = $now.AddDays(-30).ToString('yyyy-MM-ddT00:00:00Z')
$days90    = $now.AddDays(-90).ToString('yyyy-MM-ddT00:00:00Z')
$days365   = $now.AddDays(-365).ToString('yyyy-MM-ddT00:00:00Z')

foreach ($entityDef in $entityDefs) {
    $current++
    $entity        = $entityDef.LogicalName ?? $entityDef.logicalName
    $entitySetName = $entityDef.EntitySetName ?? $entityDef.entitySetName
    $primaryName   = $entityDef.PrimaryNameAttribute ?? $entityDef.primaryNameAttribute
    $primaryId     = $entityDef.PrimaryIdAttribute ?? $entityDef.primaryIdAttribute

    if (-not $entitySetName) {
        Write-Warning "[$current/$total] $entity — no EntitySetName, skipping"
        continue
    }

    Write-Host "`n[$current/$total] $entity (entitySet=$entitySetName, primaryName=$primaryName)" -ForegroundColor Yellow

    $insight = [ordered]@{ entity = $entity }

    # ── Row count ────────────────────────────────────────────────────────────
    Write-Host "  Fetching row count..." -ForegroundColor DarkCyan
    $totalCount = Get-EntityCount $entitySetName
    $insight['rowCount'] = $totalCount
    Write-Host "  Total rows: $totalCount" -ForegroundColor Cyan

    # ── Statecode breakdown (active vs inactive) ─────────────────────────────
    Write-Host "  Fetching statecode breakdown..." -ForegroundColor DarkCyan
    $activeCount   = Get-EntityCount $entitySetName "statecode eq 0"
    $inactiveCount = Get-EntityCount $entitySetName "statecode eq 1"
    $insight['statecodeBreakdown'] = [ordered]@{
        active   = $activeCount
        inactive = $inactiveCount
    }

    # ── Activity / freshness ─────────────────────────────────────────────────
    Write-Host "  Fetching activity/freshness..." -ForegroundColor DarkCyan
    $modifiedLast30  = Get-EntityCount $entitySetName "modifiedon ge $days30"
    $modifiedLast90  = Get-EntityCount $entitySetName "modifiedon ge $days90"
    $modifiedLast365 = Get-EntityCount $entitySetName "modifiedon ge $days365"
    $createdLast30   = Get-EntityCount $entitySetName "createdon ge $days30"
    $createdLast90   = Get-EntityCount $entitySetName "createdon ge $days90"

    $insight['activity'] = [ordered]@{
        modifiedLast30Days  = $modifiedLast30
        modifiedLast90Days  = $modifiedLast90
        modifiedLast365Days = $modifiedLast365
        createdLast30Days   = $createdLast30
        createdLast90Days   = $createdLast90
    }

    # Usage classification
    $insight['usageClassification'] = if ($null -eq $totalCount -or $totalCount -eq 0) {
        'empty'
    } elseif ($null -ne $modifiedLast90 -and $modifiedLast90 -gt 0) {
        'active'
    } elseif ($null -ne $modifiedLast365 -and $modifiedLast365 -gt 0) {
        'low-activity'
    } else {
        'legacy'
    }

    # ── Data quality: null primary name ──────────────────────────────────────
    if ($primaryName) {
        Write-Host "  Fetching data quality ($primaryName)..." -ForegroundColor DarkCyan
        $nullNameCount = Get-EntityCount $entitySetName "$primaryName eq null"
        $insight['dataQuality'] = [ordered]@{
            primaryNameAttribute = $primaryName
            recordsWithNullName  = $nullNameCount
            nullNamePct          = if ($totalCount -and $totalCount -gt 0 -and $null -ne $nullNameCount) {
                [math]::Round($nullNameCount / $totalCount * 100, 1)
            } else { $null }
        }
    }

    # ── Duplicate detection: records sharing primary name ────────────────────
    Write-Host "  Fetching duplicate detection..." -ForegroundColor DarkCyan
    if ($primaryName -and $totalCount -and $totalCount -gt 0 -and $totalCount -le 500000) {
        # Fetch top repeated names via groupby (FetchXml aggregate)
        $fetchXml = @"
<fetch aggregate="true" top="20">
  <entity name="$entity">
    <attribute name="$primaryName" alias="name_value" groupby="true" />
    <attribute name="$primaryId" alias="dup_count" aggregate="count" />
    <order alias="dup_count" descending="true" />
    <filter>
      <condition attribute="$primaryName" operator="not-null" />
    </filter>
  </entity>
</fetch>
"@
        try {
            $headers = @{
                Authorization      = "Bearer $($script:Connection.Token)"
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
                Accept             = 'application/json'
                Prefer             = 'odata.include-annotations="*"'
            }
            $encodedFetch = [uri]::EscapeDataString($fetchXml)
            $fetchUrl = "$($script:Connection.EnvironmentUrl)/api/data/v9.2/${entitySetName}?fetchXml=${encodedFetch}"
            $fetchResp = Invoke-RestMethod -Uri $fetchUrl -Headers $headers -Method Get
            $dupRows = $fetchResp.value | Where-Object {
                $count = $_.'dup_count'
                $count -and [int]$count -gt 1
            }
            $duplicateNames = $dupRows | ForEach-Object {
                [ordered]@{
                    name  = $_.name_value
                    count = [int]$_.'dup_count'
                }
            }
            $insight['duplicates'] = [ordered]@{
                topRepeatedNames    = @($duplicateNames)
                distinctDupNames    = ($duplicateNames | Measure-Object).Count
            }
        } catch {
            $insight['duplicates'] = [ordered]@{ error = $_.Exception.Message }
        }
    }

    # ── Relationship cardinalities (sampled) ─────────────────────────────────
    Write-Host "  Fetching relationship cardinalities..." -ForegroundColor DarkCyan
    $relFile = Join-Path $rawDir "relationships/$entity.json"
    if (Test-Path $relFile) {
        $rels = Get-Content $relFile -Raw | ConvertFrom-Json
        $cardinalities = [System.Collections.Generic.List[object]]::new()

        # Sample ManyToOne (lookup) distributions — max 5 relationships
        $m2oSample = $rels.manyToOne | Select-Object -First 5
        foreach ($rel in $m2oSample) {
            $refAttr   = $rel.ReferencingAttribute ?? $rel.referencingAttribute
            $refEntity = $rel.ReferencedEntity ?? $rel.referencedEntity
            if (-not $refAttr) { continue }

            # Count non-null FK values — lookups use _fieldname_value syntax in OData filters
            $filterAttr = "_${refAttr}_value"
            $nonNullCount = Get-EntityCount $entitySetName "$filterAttr ne null"
            $nullCount    = Get-EntityCount $entitySetName "$filterAttr eq null"

            $cardinalities.Add([ordered]@{
                relationship      = ($rel.SchemaName ?? $rel.schemaName)
                type              = 'ManyToOne'
                referencedEntity  = $refEntity
                lookupAttribute   = $refAttr
                recordsWithValue  = $nonNullCount
                recordsNull       = $nullCount
                fillRate          = if ($totalCount -and $totalCount -gt 0 -and $null -ne $nonNullCount) {
                    [math]::Round($nonNullCount / $totalCount * 100, 1)
                } else { $null }
            })
        }
        $insight['relationshipCardinalities'] = @($cardinalities)
    }

    # ── Transformation rules (plugins, workflows, business rules) ────────────
    Write-Host "  Collecting transformations..." -ForegroundColor DarkCyan
    $entityPlugins   = $pluginsByEntity[$entity]
    $entityWorkflows = $workflowsByEntity[$entity]
    Write-Host "  Plugin steps: $(if ($entityPlugins) { $entityPlugins.Count } else { 0 }), Workflows: $(if ($entityWorkflows) { $entityWorkflows.Count } else { 0 })" -ForegroundColor DarkGray

    $insight['transformations'] = [ordered]@{
        pluginSteps = if ($entityPlugins) {
            @($entityPlugins | ForEach-Object {
                [ordered]@{
                    name      = $_.name
                    stage     = $_.stage
                    mode      = $_.mode    # 0=sync, 1=async
                    statecode = $_.statecode
                }
            })
        } else { @() }
        workflows = if ($entityWorkflows) {
            @($entityWorkflows | ForEach-Object {
                $cat = switch ($_.category) {
                    0 { 'Workflow' }; 2 { 'BusinessRule' }; 3 { 'Action' }
                    4 { 'BusinessProcessFlow' }; 5 { 'PowerAutomateFlow' }
                    default { "Other_$($_.category)" }
                }
                [ordered]@{
                    name      = $_.name
                    category  = $cat
                    statecode = $_.statecode
                    type      = $_.type   # 1=Definition, 2=Activation, 3=Template
                }
            })
        } else { @() }
    }

    # ── Integration signals ──────────────────────────────────────────────────
    Write-Host "  Fetching integration signals..." -ForegroundColor DarkCyan
    $objectTypeCode = $entityDef.ObjectTypeCode ?? $entityDef.objectTypeCode
    $asyncFailed  = $null
    $asyncSuccess = $null
    if ($objectTypeCode) {
        # OData doesn't support regardingobjecttypecode filter — use FetchXml aggregate
        foreach ($statusInfo in @(
            @{ alias = 'failed';  code = 31 },
            @{ alias = 'succeeded'; code = 30 }
        )) {
            $fetchXml = @"
<fetch aggregate="true">
  <entity name="asyncoperation">
    <attribute name="asyncoperationid" alias="op_count" aggregate="count" />
    <filter>
      <condition attribute="regardingobjecttypecode" operator="eq" value="$objectTypeCode" />
      <condition attribute="statuscode" operator="eq" value="$($statusInfo.code)" />
    </filter>
  </entity>
</fetch>
"@
            try {
                $headers = @{
                    Authorization      = "Bearer $($script:Connection.Token)"
                    'OData-MaxVersion' = '4.0'
                    'OData-Version'    = '4.0'
                    Accept             = 'application/json'
                    Prefer             = 'odata.include-annotations="*"'
                }
                $encodedFetch = [uri]::EscapeDataString($fetchXml)
                $fetchUrl = "$($script:Connection.EnvironmentUrl)/api/data/v9.2/asyncoperations?fetchXml=${encodedFetch}"
                Write-Host "  [fetch] async $($statusInfo.alias) for OTC=$objectTypeCode" -ForegroundColor DarkGray
                $fetchResp = Invoke-RestMethod -Uri $fetchUrl -Headers $headers -Method Get
                $count = [int]($fetchResp.value[0].op_count)
                if ($statusInfo.alias -eq 'failed')  { $asyncFailed  = $count }
                else                                  { $asyncSuccess = $count }
                Write-Host "  [fetch] → $count" -ForegroundColor DarkGray
            } catch {
                Write-Host "  [fetch] async $($statusInfo.alias) FAILED: $($_.Exception.Message)" -ForegroundColor Red
            }
        }
    } else {
        Write-Host "  No ObjectTypeCode — skipping async operation counts" -ForegroundColor DarkGray
    }
    $insight['integrationSignals'] = [ordered]@{
        asyncOperationsFailed    = $asyncFailed
        asyncOperationsSucceeded = $asyncSuccess
    }

    # ── Write per-entity file ────────────────────────────────────────────────
    $outFile = Join-Path $outDir "$entity.json"
    $insight | ConvertTo-Json -Depth 10 | Set-Content $outFile -Encoding UTF8

    # Summary line
    $status = $insight['usageClassification']
    $rc = if ($null -ne $totalCount) { $totalCount } else { '?' }
    Write-Host "  ✓ $entity — rows=$rc status=$status" -ForegroundColor Green
}

Write-Host "`nOperational insights saved → $outDir" -ForegroundColor Green
