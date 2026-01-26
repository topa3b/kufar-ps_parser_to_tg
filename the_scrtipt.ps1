# 1. Setup Request Parameters
$url = "https://www.kufar.by/l/r~minsk/bez-posrednikov?ar=v.or%3A22%2C23%2C24%2C25%2C26%2C27%2C28%2C29%2C30&b2c=n%3A1&query=samsung+galaxy+s23+ultra&r_pageType=saved_search&sort=lst.d"

# Flag to optionally ignore already processed ads (set to $true to reprocess all ads)
# Default: $false (skip already processed ads)
$IgnoreProcessed = $false

# Path to JSON file storing processed ad_ids
$ProcessedAdsFile = ".\processed_ads.json"

# Path to config file with Telegram bot settings
$ConfigFile = ".\config.json"

# Replace 'YOUR_COOKIE_HERE' with your actual browser cookie string
$cookieValue = "lang=ru; kuf_agr={%22advertisements%22:true%2C%22advertisements-non-personalized%22:false%2C%22statistic%22:true%2C%22mindbox%22:true}; tmr_lvid=9f3bcb730ebffdc0783608de69105724; tmr_lvidTS=1741774804987; mindboxDeviceUUID=f90a2502-77f8-4c75-9b3c-cb5305a9e014; directCrm-session=%7B%22deviceGuid%22%3A%22f90a2502-77f8-4c75-9b3c-cb5305a9e014%22%7D; kuf_SA_subscribe_user_attention=1; fullscreen_cookie=1; rl_anonymous_id=RS_ENC_v3_IjUxOTE2MDJhLWYxZTMtNGIwMC05ZDk5LTI4YjA5ZWE1ODlkMyI%3D; rl_page_init_referrer=RS_ENC_v3_IiRkaXJlY3Qi; _tt_enable_cookie=1; _ttp=01K8TFHTE8RCJAQA2T71QQKXTD_.tt.1; ttcsid_CGQMK0BC77UFB25SCB7G=1761825319377::qKBNWzX85fdLFSrSTBYT.1.1761825334318.0; _gid=GA1.2.2013796532.1769368410; domain_sid=_dREB_PxSMQ9P9Vv2BCXH%3A1769368411011; _gcl_au=1.1.1902094083.1761825318.1502841158.1769368418.1769368418; k_jwt=eyJhbGciOiJIUzI1NiIsImtpZCI6InYyMCIsInNjaHYiOiIyIiwidHlwIjoiSldUIn0.eyJhaWQiOiI0MTEzOTU1IiwiY2FkIjpmYWxzZSwiZGlkIjoiZjA3NzBjZmYyMzgxMjA4OTUxOTRhMzAzZDlhNWY4YjEiLCJleHAiOjE4MDE1MDkyNTIsImlhdCI6MTc2OTM2ODQ1MiwianRpIjoiNDExMzk1NTphSjFwb0cyWSIsInB0ciI6ZmFsc2UsInR5cCI6InVzZXIifQ.oD3hiuQppT5GPeK0E_-K3yfUCIphuuSNb2s-pTIS8WQ; session_id=mc1xebb98a8a935a1d9df19561d6de491503ad536519; session=1; kufar_cart_id=84bf8842-ae08-4024-88f1-05d538a16453; supportOnlineTalkID=fd76bb9381b16b3e15e7e768278e16d5; web_push_banner_listings=3; kufar-header-ad-insertion-button-push=1; _ga=GA1.1.1948066428.1741774802; rl_session=RS_ENC_v3_eyJhdXRvVHJhY2siOnRydWUsInRpbWVvdXQiOjE4MDAwMDAsImV4cGlyZXNBdCI6MTc2OTM3NDc1NzU1MiwiaWQiOjE3NjkzNzI4NzgwNjAsInNlc3Npb25TdGFydCI6ZmFsc2V9; tmr_detect=1%7C1769372958093; _ga_ESH3WRCK3J=GS2.1.s1769372874$o9$g1$t1769372958$j60$l0$h0; _ga_QTFZM0D0BE=GS2.1.s1769372874$o9$g1$t1769372958$j60$l0$h0; ttcsid=1769373013151::YbinoYCqnJsNL82ftTdL.2.1769373023455.0; ttcsid_CRGUT0JC77UAQEJAHAL0=1769373013151::RVbRpmYlPgRmEqBUz6CX.1.1769373023458.1; kuf_VCH_promo_vas=2"

$headers = @{
    "Cookie" = $cookieValue
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

# Function to load config from JSON file
function Get-Config {
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

# Function to send message to Telegram bot
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

# Helper function to send a single message chunk to Telegram
function Send-TelegramMessageChunk {
    param (
        [string]$BotToken,
        [string]$ChatId,
        [string]$Message,
        [string]$ParseMode = "HTML"
    )
    
    $apiUrl = "https://api.telegram.org/bot$BotToken/sendMessage"
    
    $body = @{
        chat_id = $ChatId
        text = $Message
        parse_mode = $ParseMode
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

# Function to format ad results for Telegram
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

# Function to send photo to Telegram
# Helper function to truncate caption to Telegram's limit (1024 characters for photos)
# Note: Using Format verb to avoid linter warning, but this is a truncation helper
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
        chat_id = $ChatId
        photo = $PhotoUrl
        caption = $truncatedCaption
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

# Function to send media group (multiple photos) to Telegram
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
            type = "photo"
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
        media = $media
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

# Function to load processed ad_ids from JSON file
# Always returns a HashSet[int], never null
function Get-ProcessedAdIds {
    param (
        [string]$FilePath
    )
    
    # Always initialize a HashSet at the start
    $hashSet = [System.Collections.Generic.HashSet[int]]::new()
    
    try {
        # Resolve the file path to handle relative paths correctly
        $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FilePath)
        
        if (Test-Path $resolvedPath) {
            try {
                $content = Get-Content $resolvedPath -Raw | ConvertFrom-Json
                $adIdsArray = $null
                
                if ($content -is [array]) {
                    $adIdsArray = $content
                } elseif ($null -ne $content -and $null -ne $content.processed_ad_ids -and $content.processed_ad_ids -is [array]) {
                    $adIdsArray = $content.processed_ad_ids
                }
                
                if ($null -ne $adIdsArray -and $adIdsArray.Count -gt 0) {
                    Write-Host "  Found $($adIdsArray.Count) ad IDs in file" -ForegroundColor Gray
                    # Add items one by one to ensure proper type conversion
                    foreach ($id in $adIdsArray) {
                        try {
                            [void]$hashSet.Add([int]$id)
                        }
                        catch {
                            Write-Warning "Failed to add ad_id $id to HashSet: $_"
                        }
                    }
                    Write-Host "  Successfully loaded $($hashSet.Count) ad IDs into HashSet" -ForegroundColor Gray
                } else {
                    Write-Host "  No ad IDs found in file (file may be empty or have different structure)" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Warning "Failed to load processed ad_ids from $resolvedPath : $_"
            }
        } else {
            Write-Warning "File not found: $resolvedPath"
        }
    }
    catch {
        Write-Warning "Error in Get-ProcessedAdIds: $_"
    }
    finally {
        # Ensure we always have a valid HashSet before returning
        if ($null -eq $hashSet -or $hashSet -isnot [System.Collections.Generic.HashSet[int]]) {
            $hashSet = [System.Collections.Generic.HashSet[int]]::new()
        }
    }
    
    # Explicitly return HashSet - this will always be a HashSet[int]
    return $hashSet
}

# Function to save processed ad_ids to JSON file
function Save-ProcessedAdIds {
    param (
        [System.Collections.Generic.HashSet[int]]$ProcessedAdIds,
        [string]$FilePath
    )
    
    try {
        $adIdsArray = $ProcessedAdIds | Sort-Object
        $jsonContent = @{
            processed_ad_ids = $adIdsArray
            last_updated = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        } | ConvertTo-Json
        
        $jsonContent | Out-File -FilePath $FilePath -Encoding UTF8 -NoNewline
        Write-Host "Saved $($ProcessedAdIds.Count) processed ad_ids to $FilePath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to save processed ad_ids to $FilePath : $_"
    }
}

# Function to extract JSON from __NEXT_DATA__ script tag
function Get-NextDataJson {
    param (
        [string]$HtmlContent
    )
    
    $regexPattern = '(?s)<script id="__NEXT_DATA__"[^>]*>(.*?)</script>'
    if ($HtmlContent -match $regexPattern) {
        return $matches[1]
    }
    return $null
}

# Function to fetch ad details from ad_link
function Get-AdDetails {
    param (
        [string]$AdLink,
        [hashtable]$RequestHeaders,
        [int]$DelaySeconds = 0
    )
    
    # Random delay to prevent threshold and protection (1-5 seconds)
    if ($DelaySeconds -gt 0) {
        Write-Host "Waiting $DelaySeconds seconds before request..." -ForegroundColor Yellow
        Start-Sleep -Seconds $DelaySeconds
    }
    
    try {
        Write-Host "Fetching ad details from: $AdLink" -ForegroundColor Cyan
        $webResponse = Invoke-WebRequest -Uri $AdLink -Headers $RequestHeaders -UseBasicParsing
        $htmlContent = $webResponse.Content
        
        $jsonString = Get-NextDataJson -HtmlContent $htmlContent
        if ($null -eq $jsonString) {
            Write-Warning "Could not find __NEXT_DATA__ in ad page: $AdLink"
            return $null
        }
        
        $data = $jsonString | ConvertFrom-Json -AsHashTable
        
        # Extract description and gallery images
        $description = $data.props.initialState.adView.data.description
        $galleryImages = $data.props.initialState.adView.data.gallery.thumbnails
        
        return @{
            Description = $description
            GalleryImages = $galleryImages
            Success = $true
        }
    }
    catch {
        Write-Warning "Failed to fetch ad details from $AdLink : $_"
        return @{
            Description = $null
            GalleryImages = $null
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

# Main function to process ads
function Start-AdProcessing {
    param (
        [string]$Url,
        [hashtable]$Headers,
        [bool]$IgnoreProcessed,
        [string]$ProcessedAdsFile,
        [string]$ConfigFile
    )
    
    try {
        # 2. Load config for Telegram bot
    Write-Host "Loading config from $ConfigFile..." -ForegroundColor Cyan
    $config = Get-Config -FilePath $ConfigFile
    $telegramEnabled = $false
    $botToken = $null
    $chatId = $null
    
    if ($null -ne $config) {
        $botToken = $config.telegram.bot_token
        $chatId = $config.telegram.chat_id
        if (-not [string]::IsNullOrWhiteSpace($botToken) -and -not [string]::IsNullOrWhiteSpace($chatId)) {
            $telegramEnabled = $true
            Write-Host "Telegram notifications enabled" -ForegroundColor Green
        } else {
            Write-Warning "Telegram bot token or chat ID is missing in config. Telegram notifications will be disabled."
        }
    } else {
        Write-Warning "Failed to load config. Telegram notifications will be disabled."
    }
    
    # 3. Load processed ad_ids
    Write-Host "Loading processed ad_ids from $ProcessedAdsFile..." -ForegroundColor Cyan
    $processedAdIds = Get-ProcessedAdIds -FilePath $ProcessedAdsFile
    # Ensure $processedAdIds is always a HashSet
    if ($null -eq $processedAdIds) {
        Write-Host "No processed ad_ids found (starting fresh)" -ForegroundColor Yellow
        $processedAdIds = [System.Collections.Generic.HashSet[int]]::new()
    } else {
        Write-Host "Found $($processedAdIds.Count) already processed ad_ids" -ForegroundColor Yellow
    }
    
    if ($IgnoreProcessed) {
        Write-Host "IgnoreProcessed flag is set to `$true - will reprocess all ads" -ForegroundColor Yellow
    }

    # 4. Fetch the listing page content
    Write-Host "Fetching listing page content..." -ForegroundColor Cyan
    try {
        $webResponse = Invoke-WebRequest -Uri $Url -Headers $Headers -UseBasicParsing
        if ($null -eq $webResponse) {
            throw "Web response is null"
        }
        $htmlContent = $webResponse.Content
        if ($null -eq $htmlContent) {
            throw "HTML content is null"
        }
        Write-Host "Successfully fetched page content (length: $($htmlContent.Length) characters)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to fetch listing page: $_"
        throw
    }

    # 5. Extract the JSON from the __NEXT_DATA__ script tag
    Write-Host "Extracting JSON from __NEXT_DATA__..." -ForegroundColor Cyan
    try {
        $jsonString = Get-NextDataJson -HtmlContent $htmlContent
        if ($null -eq $jsonString -or $jsonString.Length -eq 0) {
            Write-Error "Could not find the __NEXT_DATA__ script tag in the page source."
            exit 1
        }
        Write-Host "Successfully extracted JSON (length: $($jsonString.Length) characters)" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to extract JSON from page: $_"
        throw
    }

    # 6. Parse JSON
    Write-Host "Parsing JSON..." -ForegroundColor Cyan
    try {
        $data = $jsonString | ConvertFrom-Json -AsHashTable
        if ($null -eq $data) {
            throw "Parsed JSON data is null"
        }
        Write-Host "Successfully parsed JSON" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to parse JSON: $_"
        throw
    }

    # 7. Access the ads list with null checks
    if ($null -eq $data -or $null -eq $data.props -or $null -eq $data.props.initialState -or 
        $null -eq $data.props.initialState.listing -or $null -eq $data.props.initialState.listing.ads) {
        Write-Error "Could not find ads in the expected data structure. The page structure may have changed."
        Write-Host "Available top-level keys: $($data.Keys -join ', ')" -ForegroundColor Yellow
        if ($data.props) {
            Write-Host "Available props keys: $($data.props.Keys -join ', ')" -ForegroundColor Yellow
        }
        exit 1
    }
    
    $allAds = $data.props.initialState.listing.ads
    
    if ($null -eq $allAds) {
        Write-Error "Ads list is null or empty."
        exit 1
    }

    # 8. Filter ads based on processed list (unless IgnoreProcessed is true)
    if ($IgnoreProcessed) {
        $ads = $allAds;
        if ($null -ne $ads) {
            Write-Host "Processing all $($ads.Count) advertisements (ignoring processed list)`n" -ForegroundColor Green
        } else {
            Write-Host "No ads found to process`n" -ForegroundColor Yellow
        }
    } else {
        if ($null -ne $allAds) {
            # filter out $allAds to leave only ads that are not in $processedAdIds
            $ads = $allAds | Where-Object { -not $processedAdIds.Contains([int]$_.ad_id) }
            # Ensure $ads is an array even if Where-Object returns null
            if ($null -eq $ads) {
                $ads = @()
            }
            $skippedCount = $allAds.Count - $ads.Count
            Write-Host "Successfully extracted $($allAds.Count) total advertisements" -ForegroundColor Green
            Write-Host "Skipping $skippedCount already processed ads" -ForegroundColor Yellow
            Write-Host "Processing $($ads.Count) new advertisements`n" -ForegroundColor Green
        } else {
            $ads = @()
            Write-Host "No ads found to process`n" -ForegroundColor Yellow
        }
    }

    # 9. Display initial ad list
    if ($null -ne $ads -and $ads.Count -gt 0) {
        Write-Host "Initial Ad List:" -ForegroundColor Green
        $ads | Select-Object `
            @{Name="Ad_ID"; Expression={$_.ad_id}},
            @{Name="Title"; Expression={$_.subject}}, 
            @{Name="Price_BYN"; Expression={$_.price_byn / 100}}, # Price is stored in cents
            @{Name="Link"; Expression={$_.ad_link}},
            @{Name="Region"; Expression={$_.ad_parameters | Where-Object {$_.p -eq "area"} | Select-Object -ExpandProperty vl}} | 
            Format-Table -AutoSize

        Write-Host "`nFetching detailed information from each ad...`n" -ForegroundColor Green

        # 10. Fetch details from each ad_link
        $results = @()
        $random = New-Object System.Random
        $newlyProcessedCount = 0
        $adIndex = 0
        
        $ads | ForEach-Object {
            $ad = $_;
            $adIndex++
            
            $adTitle = if ($null -ne $ad.subject) { $ad.subject } else { "Unknown" }
            $adId = if ($null -ne $ad.ad_id) { $ad.ad_id } else { "Unknown" }
            Write-Host "`n[$adIndex/$($ads.Count)] Processing: $adTitle (ID: $adId)" -ForegroundColor Cyan
            
            if ($null -eq $ad.ad_link -or [string]::IsNullOrWhiteSpace($ad.ad_link)) {
                Write-Warning "Ad link is null or empty for ad ID: $adId, skipping..."
                return
            }
            
            # Double-check that this ad hasn't been processed (safety check)
            if ($null -ne $ad.ad_id -and -not $IgnoreProcessed) {
                $adIdInt = [int]$ad.ad_id
                if ($processedAdIds.Contains($adIdInt)) {
                    Write-Host "  - Ad ID $adId already processed, skipping Get-AdDetails" -ForegroundColor Yellow
                    return
                }
            }
            
            # Random delay between 1-3 seconds (except for first request)
            $delay = if ($adIndex -eq 1) { 0 } else { $random.Next(1, 3) }
            
            $adDetails = Get-AdDetails -AdLink $ad.ad_link -RequestHeaders $Headers -DelaySeconds $delay
            
            $price = if ($null -ne $ad.price_byn) { $ad.price_byn / 100 } else { 0 }
            $region = if ($null -ne $ad.ad_parameters) { 
                ($ad.ad_parameters | Where-Object {$_.p -eq "area"} | Select-Object -ExpandProperty vl)
            } else { 
                $null 
            }
            
            # Extract list_time
            $listTime = if ($null -ne $ad.list_time) { $ad.list_time } else { $null }
            
            # Clean up description: remove multiple consecutive newlines
            $cleanDescription = if ($null -ne $adDetails -and $adDetails.Success -and $null -ne $adDetails.Description) { 
                # Replace multiple consecutive newlines (including \r\n, \n, \r) with a single newline
                ($adDetails.Description -replace '(?:\r\n|\r|\n){2,}', "`n").Trim()
            } else { 
                "Failed to fetch" 
            }
            
            $result = [PSCustomObject]@{
                Ad_ID = $ad.ad_id
                Title = if ($null -ne $ad.subject) { $ad.subject } else { "Unknown" }
                Price_BYN = $price
                Link = $ad.ad_link
                Region = $region
                ListTime = $listTime
                Description = $cleanDescription
                ImageCount = if ($null -ne $adDetails -and $adDetails.Success -and $null -ne $adDetails.GalleryImages) { $adDetails.GalleryImages.Count } else { 0 }
                Images = if ($null -ne $adDetails -and $adDetails.Success -and $null -ne $adDetails.GalleryImages) { $adDetails.GalleryImages } else { @() }
                FetchSuccess = if ($null -ne $adDetails) { $adDetails.Success } else { $false }
            }
            
            $results += $result
            
            # Display summary for this ad
            if ($null -ne $adDetails -and $adDetails.Success) {
                $descLength = if ($null -ne $result.Description) { $result.Description.Length } else { 0 }
                Write-Host "  - Description: $descLength characters" -ForegroundColor Green
                Write-Host "  - Gallery Images: $($result.ImageCount)" -ForegroundColor Green
                # Mark as processed only if fetch was successful
                if ($null -ne $ad.ad_id) {
                    $adIdInt = [int]$ad.ad_id
                    # Ensure $processedAdIds is a HashSet before adding
                    if ($processedAdIds -isnot [System.Collections.Generic.HashSet[int]]) {
                        Write-Warning "processedAdIds is not a HashSet, recreating..."
                        $tempSet = [System.Collections.Generic.HashSet[int]]::new()
                        if ($null -ne $processedAdIds) {
                            foreach ($existingId in $processedAdIds) {
                                [void]$tempSet.Add([int]$existingId)
                            }
                        }
                        $processedAdIds = $tempSet
                    }
                    if ($processedAdIds.Add($adIdInt)) {
                        $newlyProcessedCount++
                    }
                }
            } else {
                Write-Host "  ✗ Failed to fetch details" -ForegroundColor Red
            }
        }
        
        # 11. Save processed ad_ids to JSON file
        if ($newlyProcessedCount -gt 0) {
            Write-Host "`nSaving $newlyProcessedCount newly processed ad_ids..." -ForegroundColor Cyan
            Save-ProcessedAdIds -ProcessedAdIds $processedAdIds -FilePath $ProcessedAdsFile
        } else {
            Write-Host "`nNo new ads processed, skipping save." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No new ads to process. All ads have already been processed." -ForegroundColor Yellow
        $results = @()
    }

    # 12. Display final results summary
    if ($results.Count -gt 0) {
        Write-Host "`n" -NoNewline
        Write-Host "=" * 80 -ForegroundColor Green
        Write-Host "FINAL RESULTS SUMMARY" -ForegroundColor Green
        Write-Host "=" * 80 -ForegroundColor Green
        
        $results | Select-Object `
            Ad_ID,
            Title,
            Price_BYN,
            @{Name="Description_Length"; Expression={$_.Description.Length}},
            ImageCount,
            FetchSuccess | 
            Format-Table -AutoSize
        
        # 13. Display detailed results with descriptions and image URLs
        Write-Host "`nDETAILED RESULTS:" -ForegroundColor Green
        foreach ($result in $results) {
            Write-Host "`n" + ("=" * 80) -ForegroundColor Cyan
            Write-Host "Ad ID: $($result.Ad_ID)" -ForegroundColor White
            Write-Host "Title: $($result.Title)" -ForegroundColor White
            Write-Host "Price: $($result.Price_BYN) BYN" -ForegroundColor White
            Write-Host "Link: $($result.Link)" -ForegroundColor White
            Write-Host "Region: $($result.Region)" -ForegroundColor White
            Write-Host "Description: $($result.Description)" -ForegroundColor White
            Write-Host "Images ($($result.ImageCount)):" -ForegroundColor White
            if ($result.Images.Count -gt 0) {
                foreach ($img in $result.Images) {
                    $imgUrl = if ($img.url) { $img.url } else { $img }
                    Write-Host "  - $imgUrl" -ForegroundColor Gray
                }
            }
        }
        
        # 14. Send results to Telegram
        if ($telegramEnabled) {
            Write-Host "`nSending results to Telegram..." -ForegroundColor Cyan
            
            if ($results.Count -eq 1) {
                # Single ad - send with photos
                $result = $results[0]
                $telegramMessage = Format-AdForTelegram -AdResult $result
                
                # Extract image URLs
                $imageUrls = @()
                if ($result.Images -and $result.Images.Count -gt 0) {
                    foreach ($img in $result.Images) {
                        $imgUrl = $null
                        if ($img -is [hashtable] -or $img -is [PSCustomObject]) {
                            # Try common URL properties
                            if ($img.url) { $imgUrl = $img.url }
                            elseif ($img.src) { $imgUrl = $img.src }
                            elseif ($img.href) { $imgUrl = $img.href }
                        } elseif ($img -is [string]) {
                            $imgUrl = $img
                        }
                        if ($imgUrl -and -not [string]::IsNullOrWhiteSpace($imgUrl)) {
                            $imageUrls += $imgUrl
                        }
                    }
                }
                
                # Send photos with message
                if ($imageUrls.Count -gt 0) {
                    if ($imageUrls.Count -eq 1) {
                        # Single photo
                        Send-TelegramPhoto -BotToken $botToken -ChatId $chatId -PhotoUrl $imageUrls[0] -Caption $telegramMessage | Out-Null
                    } else {
                        # Multiple photos - use media group
                        Send-TelegramMediaGroup -BotToken $botToken -ChatId $chatId -PhotoUrls $imageUrls -Caption $telegramMessage | Out-Null
                    }
                } else {
                    # No photos - send text message only
                    Send-TelegramMessage -BotToken $botToken -ChatId $chatId -Message $telegramMessage | Out-Null
                }
            } else {
                # Multiple ads - send each ad with photos
                foreach ($result in $results) {
                    $telegramMessage = Format-AdForTelegram -AdResult $result
                    
                    # Extract image URLs
                    $imageUrls = @()
                    if ($result.Images -and $result.Images.Count -gt 0) {
                        foreach ($img in $result.Images) {
                            $imgUrl = $null
                            if ($img -is [hashtable] -or $img -is [PSCustomObject]) {
                                # Try common URL properties
                                if ($img.url) { $imgUrl = $img.url }
                                elseif ($img.src) { $imgUrl = $img.src }
                                elseif ($img.href) { $imgUrl = $img.href }
                            } elseif ($img -is [string]) {
                                $imgUrl = $img
                            }
                            if ($imgUrl -and -not [string]::IsNullOrWhiteSpace($imgUrl)) {
                                $imageUrls += $imgUrl
                            }
                        }
                    }
                    
                    # Send photos with message
                    if ($imageUrls.Count -gt 0) {
                        if ($imageUrls.Count -eq 1) {
                            # Single photo
                            Send-TelegramPhoto -BotToken $botToken -ChatId $chatId -PhotoUrl $imageUrls[0] -Caption $telegramMessage | Out-Null
                        } else {
                            # Multiple photos - use media group
                            Send-TelegramMediaGroup -BotToken $botToken -ChatId $chatId -PhotoUrls $imageUrls -Caption $telegramMessage | Out-Null
                        }
                    } else {
                        # No photos - send text message only
                        Send-TelegramMessage -BotToken $botToken -ChatId $chatId -Message $telegramMessage | Out-Null
                    }
                    
                    # Small delay between messages to avoid rate limiting
                    Start-Sleep -Milliseconds 500
                }
            }
            
            Write-Host "Telegram notifications sent" -ForegroundColor Green
        }
    } else {
        Write-Host "`nNo results to display." -ForegroundColor Yellow
    }
}
    catch {
        Write-Error "Failed to retrieve or parse data: $_"
    }
}

# Call the main function
# Start-AdProcessing arguments:
#   -Url: Kufar listing URL to scrape
#   -Headers: HTTP headers hashtable containing Cookie and User-Agent
#   -IgnoreProcessed: Boolean flag - if $true, reprocess all ads; if $false, skip already processed ads
#   -ProcessedAdsFile: Path to JSON file storing processed ad IDs
#   -ConfigFile: Path to JSON config file with Telegram bot settings
Start-AdProcessing `
    -Url $url `
    -Headers $headers `
    -IgnoreProcessed $IgnoreProcessed `
    -ProcessedAdsFile $ProcessedAdsFile `
    -ConfigFile $ConfigFile