<#
.SYNOPSIS
    Telegram Bot API helpers: load config, send messages, photos, media groups, and format ad summaries.
.DESCRIPTION
    Reusable functions for scripts that notify via Telegram. Requires config JSON with telegram.bot_token and telegram.chat_id.
#>

function Get-TelegramConfig {
    param (
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath)) {
        Write-Error "Config file not found: $FilePath. Please create it with telegram.bot_token and telegram.chat_id"
        return $null
    }

    try {
        $content = Get-Content $FilePath -Raw | ConvertFrom-Json
        if ($null -eq $content.telegram -or
            [string]::IsNullOrWhiteSpace($content.telegram.bot_token) -or
            [string]::IsNullOrWhiteSpace($content.telegram.chat_id)) {
            Write-Error "Config file is missing telegram.bot_token or telegram.chat_id"
            return $null
        }
        return $content
    }
    catch {
        Write-Error "Failed to load config from $FilePath : $_"
        return $null
    }
}

function Send-TelegramMessage {
    param (
        [string]$BotToken,
        [string]$ChatId,
        [string]$Message,
        [string]$ParseMode = "HTML"
    )

    if ([string]::IsNullOrWhiteSpace($BotToken) -or [string]::IsNullOrWhiteSpace($ChatId)) {
        Write-Warning "Telegram bot token or chat ID is missing. Skipping Telegram notification."
        return $false
    }

    # Telegram API has a 4096 character limit per message
    $maxLength = 4096
    if ($Message.Length -gt $maxLength) {
        # Split message into chunks
        $chunks = @()
        $currentChunk = ""
        $lines = $Message -split "`n"

        foreach ($line in $lines) {
            if (($currentChunk.Length + $line.Length + 1) -gt $maxLength) {
                if ($currentChunk.Length -gt 0) {
                    $chunks += $currentChunk
                    $currentChunk = $line
                } else {
                    # Line itself is too long, truncate it
                    $chunks += $line.Substring(0, $maxLength - 3) + "..."
                    $currentChunk = ""
                }
            } else {
                if ($currentChunk.Length -gt 0) {
                    $currentChunk += "`n" + $line
                } else {
                    $currentChunk = $line
                }
            }
        }
        if ($currentChunk.Length -gt 0) {
            $chunks += $currentChunk
        }

        # Send each chunk
        $success = $true
        for ($i = 0; $i -lt $chunks.Count; $i++) {
            $chunkMessage = if ($chunks.Count -gt 1) {
                "Part $($i + 1)/$($chunks.Count)`n`n" + $chunks[$i]
            } else {
                $chunks[$i]
            }
            if (-not (Send-TelegramMessageChunk -BotToken $BotToken -ChatId $ChatId -Message $chunkMessage -ParseMode $ParseMode)) {
                $success = $false
            }
            # Small delay between chunks
            if ($i -lt $chunks.Count - 1) {
                Start-Sleep -Milliseconds 500
            }
        }
        return $success
    } else {
        return Send-TelegramMessageChunk -BotToken $BotToken -ChatId $ChatId -Message $Message -ParseMode $ParseMode
    }
}

function Send-TelegramMessageChunk {
    param (
        [string]$BotToken,
        [string]$ChatId,
        [string]$Message,
        [string]$ParseMode = "HTML"
    )

    $apiUrl = "https://api.telegram.org/bot$BotToken/sendMessage"

    $body = @{
        chat_id                  = $ChatId
        text                     = $Message
        parse_mode               = $ParseMode
        disable_web_page_preview = $false
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "✓ Message sent to Telegram successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to send message to Telegram: $_"
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Warning "Response: $responseBody"
        }
        return $false
    }
}

function Format-AdForTelegram {
    param (
        [PSCustomObject]$AdResult
    )

    $message = "<b>$($AdResult.Title)</b>`n"
    $message += "<b>$($AdResult.Price_BYN) BYN</b>`n"
    $message += "$($AdResult.Region)`n"

    # Format list_time if available
    if ($AdResult.ListTime -and -not [string]::IsNullOrWhiteSpace($AdResult.ListTime)) {
        try {
            $listDate = [DateTime]::Parse($AdResult.ListTime)
            $formattedDate = $listDate.ToString("yyyy-MM-dd HH:mm")
            $message += "Posted: $formattedDate`n"
        }
        catch {
            # If parsing fails, use the original string
            $message += "Posted: $($AdResult.ListTime)`n"
        }
    }

    $message += "<a href=`"$($AdResult.Link)`">View on Kufar</a>`n"
    $message += "`n"

    if ($AdResult.Description -and $AdResult.Description -ne "Failed to fetch") {
        # Escape HTML special characters and limit description length
        # Limit to 800 chars to leave room for title, price, region, date, link, ID (total caption limit is 1024)
        $desc = $AdResult.Description -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;'
        if ($desc.Length -gt 800) {
            $desc = $desc.Substring(0, 800) + "..."
        }
        $message += "<i>$desc</i>`n"
        $message += "`n"
    }

    $message += "ID: $($AdResult.Ad_ID)"

    return $message
}

function Format-TelegramCaption {
    param (
        [string]$Caption,
        [int]$MaxLength = 1024
    )

    if ([string]::IsNullOrWhiteSpace($Caption)) {
        return $Caption
    }

    if ($Caption.Length -le $MaxLength) {
        return $Caption
    }

    # Truncate and add ellipsis, but try to preserve HTML tags
    $truncated = $Caption.Substring(0, $MaxLength - 3)

    # Try to close any open HTML tags by finding the last complete tag
    $lastTagIndex = $truncated.LastIndexOf('<')
    if ($lastTagIndex -gt 0) {
        $afterLastTag = $truncated.Substring($lastTagIndex)
        # If we're in the middle of a tag, truncate before it
        if ($afterLastTag -notmatch '^<[^>]+>$') {
            $truncated = $truncated.Substring(0, $lastTagIndex)
        }
    }

    return $truncated + "..."
}

function Send-TelegramPhoto {
    param (
        [string]$BotToken,
        [string]$ChatId,
        [string]$PhotoUrl,
        [string]$Caption = ""
    )

    if ([string]::IsNullOrWhiteSpace($BotToken) -or [string]::IsNullOrWhiteSpace($ChatId)) {
        Write-Warning "Telegram bot token or chat ID is missing. Skipping photo."
        return $false
    }

    # Telegram photo caption limit is 1024 characters
    $truncatedCaption = Format-TelegramCaption -Caption $Caption -MaxLength 1024

    $apiUrl = "https://api.telegram.org/bot$BotToken/sendPhoto"

    $body = @{
        chat_id    = $ChatId
        photo      = $PhotoUrl
        caption    = $truncatedCaption
        parse_mode = "HTML"
    } | ConvertTo-Json

    try {
        Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "Photo sent to Telegram successfully" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to send photo to Telegram: $_"
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Warning "Response: $responseBody"
        }
        return $false
    }
}

function Send-TelegramMediaGroup {
    param (
        [string]$BotToken,
        [string]$ChatId,
        [array]$PhotoUrls,
        [string]$Caption = ""
    )

    if ([string]::IsNullOrWhiteSpace($BotToken) -or [string]::IsNullOrWhiteSpace($ChatId)) {
        Write-Warning "Telegram bot token or chat ID is missing. Skipping media group."
        return $false
    }

    # Telegram allows max 10 photos per media group
    $maxPhotos = 10
    $photosToSend = $PhotoUrls[0..([Math]::Min($PhotoUrls.Count - 1, $maxPhotos - 1))]

    $apiUrl = "https://api.telegram.org/bot$BotToken/sendMediaGroup"

    # Telegram photo caption limit is 1024 characters
    $truncatedCaption = Format-TelegramCaption -Caption $Caption -MaxLength 1024

    $media = @()
    for ($i = 0; $i -lt $photosToSend.Count; $i++) {
        $mediaItem = @{
            type  = "photo"
            media = $photosToSend[$i]
        }
        # Add caption only to the first photo
        if ($i -eq 0 -and -not [string]::IsNullOrWhiteSpace($truncatedCaption)) {
            $mediaItem.caption = $truncatedCaption
            $mediaItem.parse_mode = "HTML"
        }
        $media += $mediaItem
    }

    $body = @{
        chat_id = $ChatId
        media   = $media
    } | ConvertTo-Json -Depth 10

    try {
        Invoke-RestMethod -Uri $apiUrl -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop | Out-Null
        Write-Host "Media group sent to Telegram successfully ($($photosToSend.Count) photos)" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Warning "Failed to send media group to Telegram: $_"
        if ($_.Exception.Response) {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
            Write-Warning "Response: $responseBody"
        }
        return $false
    }
}

Export-ModuleMember -Function @(
    'Get-TelegramConfig',
    'Send-TelegramMessage',
    'Format-AdForTelegram',
    'Format-TelegramCaption',
    'Send-TelegramPhoto',
    'Send-TelegramMediaGroup'
)
