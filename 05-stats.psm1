<#
.SYNOPSIS
    Cost statistics module: save and retrieve item cost history in a CSV file DB.
.DESCRIPTION
    Records contain: item_id, cost, date_taken.
    Duplicate check: a new record is added only when the cost for an existing item has changed.
#>

# Default path for the cost statistics CSV DB file
$script:DefaultCostStatsDbPath = Join-Path (Get-Location) "cost_stats.csv"

function Get-CostStatsDbPath {
    param([string]$DbPath)
    if ([string]::IsNullOrWhiteSpace($DbPath)) {
        return $script:DefaultCostStatsDbPath
    }
    return $DbPath
}

function Get-CostStatsDb {
    <#
    .SYNOPSIS
        Loads the cost stats DB from CSV file. Returns array of records.
    #>
    param(
        [string]$DbPath = $script:DefaultCostStatsDbPath
    )
    $resolvedPath = Get-CostStatsDbPath -DbPath $DbPath
    if (-not (Test-Path $resolvedPath)) {
        return @()
    }
    try {
        $records = Import-Csv -Path $resolvedPath -Encoding UTF8
        if ($null -eq $records) {
            return @()
        }
        return @($records)
    }
    catch {
        Write-Warning "Failed to load cost stats DB from $resolvedPath : $_"
        return @()
    }
}

function Save-CostStatsDb {
    <#
    .SYNOPSIS
        Saves the records array to the cost stats CSV file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [array]$Records,
        [string]$DbPath = $script:DefaultCostStatsDbPath
    )
    $resolvedPath = Get-CostStatsDbPath -DbPath $DbPath
    try {
        $Records | Export-Csv -Path $resolvedPath -Encoding UTF8 -NoTypeInformation
        return $true
    }
    catch {
        Write-Warning "Failed to save cost stats DB to $resolvedPath : $_"
        return $false
    }
}

function Save-CostStat {
    <#
    .SYNOPSIS
        Saves a cost record for an item. Adds a new record only if the cost has changed from the last recorded value (duplicate check).
    .PARAMETER ItemId
        ID of the item (e.g. ad_id).
    .PARAMETER Cost
        Cost value to record.
    .PARAMETER DateTaken
        When the cost was taken. Default: current UTC date/time (ISO format).
    .PARAMETER DbPath
        Path to the CSV DB file. Default: cost_stats.csv in current directory.
    .OUTPUTS
        $true if a new record was added, $false if skipped (duplicate cost) or on error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ItemId,
        [Parameter(Mandatory = $true)]
        [double]$Cost,
        [DateTime]$DateTaken = ([DateTime]::UtcNow),
        [string]$DbPath = $script:DefaultCostStatsDbPath
    )
    $resolvedPath = Get-CostStatsDbPath -DbPath $DbPath
    $records = @(Get-CostStatsDb -DbPath $resolvedPath)

    # Get latest record for this item (by date_taken)
    $latestForItem = $records |
        Where-Object { $_.item_id -eq $ItemId } |
        Sort-Object { [DateTime]$_.date_taken } -Descending |
        Select-Object -First 1

    # Duplicate check: if latest cost equals new cost, skip
    if ($null -ne $latestForItem) {
        $lastCost = [double]$latestForItem.cost
        if ([Math]::Abs($lastCost - $Cost) -lt 0.0001) {
            return $false
        }
    }

    $dateStr = $DateTaken.ToString("o")
    $newRecord = [PSCustomObject]@{
        item_id    = $ItemId
        cost       = $Cost
        date_taken = $dateStr
    }
    $records += $newRecord
    return Save-CostStatsDb -Records $records -DbPath $resolvedPath
}

function Get-CostStats {
    <#
    .SYNOPSIS
        Retrieves cost statistics from the DB for all items: total count, min, max, average, median. Optional date range filter.
    .PARAMETER FromDate
        Start of period (date_taken >= this date). If neither FromDate nor ToDate is set, past month is used.
    .PARAMETER ToDate
        End of period (date_taken <= this date). If neither FromDate nor ToDate is set, past month is used.
    .PARAMETER DbPath
        Path to the CSV DB file.
    .OUTPUTS
        Object with TotalCount, Min, Max, Average, Median, and Records (filtered list).
    #>
    [CmdletBinding()]
    param(
        [DateTime]$FromDate = [DateTime]::MinValue,
        [DateTime]$ToDate = [DateTime]::MinValue,
        [string]$DbPath = $script:DefaultCostStatsDbPath
    )
    $resolvedPath = Get-CostStatsDbPath -DbPath $DbPath
    $records = @(Get-CostStatsDb -DbPath $resolvedPath)

    if ($records.Count -eq 0) {
        return [PSCustomObject]@{
            TotalCount = 0
            Min        = $null
            Max        = $null
            Average    = $null
            Median     = $null
            Records    = @()
        }
    }

    # If no period defined, use past month
    $noPeriodDefined = ($FromDate -eq [DateTime]::MinValue -and $ToDate -eq [DateTime]::MinValue)
    if ($noPeriodDefined) {
        $ToDate = [DateTime]::UtcNow
        $FromDate = $ToDate.AddMonths(-1)
    }
    if ($FromDate -ne [DateTime]::MinValue) {
        $fromStr = $FromDate.ToString("o")
        $records = $records | Where-Object { [string]$_.date_taken -ge $fromStr }
    }
    if ($ToDate -ne [DateTime]::MinValue) {
        $toStr = $ToDate.ToString("o")
        $records = $records | Where-Object { [string]$_.date_taken -le $toStr }
    }

    $count = $records.Count
    if ($count -eq 0) {
        return [PSCustomObject]@{
            TotalCount = 0
            Min        = $null
            Max        = $null
            Average    = $null
            Median     = $null
            Records    = @()
        }
    }

    $costs = @($records | ForEach-Object { [double]$_.cost })
    $min = ($costs | Measure-Object -Minimum).Minimum
    $max = ($costs | Measure-Object -Maximum).Maximum
    $average = ($costs | Measure-Object -Average).Average
    $sorted = @($costs | Sort-Object)
    $mid = [int][Math]::Floor($count / 2)
    if ($count % 2 -eq 1) {
        $median = $sorted[$mid]
    } else {
        $median = ($sorted[$mid - 1] + $sorted[$mid]) / 2
    }

    return [PSCustomObject]@{
        TotalCount = $count
        Min        = $min
        Max        = $max
        Average    = $average
        Median     = $median
        Records    = @($records)
    }
}

Export-ModuleMember -Function Save-CostStat, Get-CostStats, Get-CostStatsDbPath
