# 1. Setup Request Parameters
$url = "https://www.kufar.by/l/r~minsk/bez-posrednikov?ar=v.or%3A22%2C23%2C24%2C25%2C26%2C27%2C28%2C29%2C30&b2c=n%3A1&query=samsung+galaxy+s23+ultra&r_pageType=saved_search&sort=lst.d"

# Flag to optionally ignore already processed ads (set to $true to reprocess all ads)
# Default: $false (skip already processed ads)
$IgnoreProcessed = $false

# Path to JSON file storing processed ad_ids
$ProcessedAdsFile = "processed_ads.json"

# Replace 'YOUR_COOKIE_HERE' with your actual browser cookie string
$cookieValue = "lang=ru; kuf_agr={%22advertisements%22:true%2C%22advertisements-non-personalized%22:false%2C%22statistic%22:true%2C%22mindbox%22:true}; tmr_lvid=9f3bcb730ebffdc0783608de69105724; tmr_lvidTS=1741774804987; mindboxDeviceUUID=f90a2502-77f8-4c75-9b3c-cb5305a9e014; directCrm-session=%7B%22deviceGuid%22%3A%22f90a2502-77f8-4c75-9b3c-cb5305a9e014%22%7D; kuf_SA_subscribe_user_attention=1; fullscreen_cookie=1; rl_anonymous_id=RS_ENC_v3_IjUxOTE2MDJhLWYxZTMtNGIwMC05ZDk5LTI4YjA5ZWE1ODlkMyI%3D; rl_page_init_referrer=RS_ENC_v3_IiRkaXJlY3Qi; _tt_enable_cookie=1; _ttp=01K8TFHTE8RCJAQA2T71QQKXTD_.tt.1; ttcsid_CGQMK0BC77UFB25SCB7G=1761825319377::qKBNWzX85fdLFSrSTBYT.1.1761825334318.0; _gid=GA1.2.2013796532.1769368410; domain_sid=_dREB_PxSMQ9P9Vv2BCXH%3A1769368411011; _gcl_au=1.1.1902094083.1761825318.1502841158.1769368418.1769368418; k_jwt=eyJhbGciOiJIUzI1NiIsImtpZCI6InYyMCIsInNjaHYiOiIyIiwidHlwIjoiSldUIn0.eyJhaWQiOiI0MTEzOTU1IiwiY2FkIjpmYWxzZSwiZGlkIjoiZjA3NzBjZmYyMzgxMjA4OTUxOTRhMzAzZDlhNWY4YjEiLCJleHAiOjE4MDE1MDkyNTIsImlhdCI6MTc2OTM2ODQ1MiwianRpIjoiNDExMzk1NTphSjFwb0cyWSIsInB0ciI6ZmFsc2UsInR5cCI6InVzZXIifQ.oD3hiuQppT5GPeK0E_-K3yfUCIphuuSNb2s-pTIS8WQ; session_id=mc1xebb98a8a935a1d9df19561d6de491503ad536519; session=1; kufar_cart_id=84bf8842-ae08-4024-88f1-05d538a16453; supportOnlineTalkID=fd76bb9381b16b3e15e7e768278e16d5; web_push_banner_listings=3; kufar-header-ad-insertion-button-push=1; _ga=GA1.1.1948066428.1741774802; rl_session=RS_ENC_v3_eyJhdXRvVHJhY2siOnRydWUsInRpbWVvdXQiOjE4MDAwMDAsImV4cGlyZXNBdCI6MTc2OTM3NDc1NzU1MiwiaWQiOjE3NjkzNzI4NzgwNjAsInNlc3Npb25TdGFydCI6ZmFsc2V9; tmr_detect=1%7C1769372958093; _ga_ESH3WRCK3J=GS2.1.s1769372874$o9$g1$t1769372958$j60$l0$h0; _ga_QTFZM0D0BE=GS2.1.s1769372874$o9$g1$t1769372958$j60$l0$h0; ttcsid=1769373013151::YbinoYCqnJsNL82ftTdL.2.1769373023455.0; ttcsid_CRGUT0JC77UAQEJAHAL0=1769373013151::RVbRpmYlPgRmEqBUz6CX.1.1769373023458.1; kuf_VCH_promo_vas=2"

$headers = @{
    "Cookie" = $cookieValue
    "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

# Function to load processed ad_ids from JSON file
function Get-ProcessedAdIds {
    param (
        [string]$FilePath
    )
    
    if (Test-Path $FilePath) {
        try {
            $content = Get-Content $FilePath -Raw | ConvertFrom-Json
            if ($content -is [array]) {
                return [System.Collections.Generic.HashSet[int]]::new($content)
            } elseif ($content.processed_ad_ids -is [array]) {
                return [System.Collections.Generic.HashSet[int]]::new($content.processed_ad_ids)
            } else {
                return [System.Collections.Generic.HashSet[int]]::new()
            }
        }
        catch {
            Write-Warning "Failed to load processed ad_ids from $FilePath : $_"
            return [System.Collections.Generic.HashSet[int]]::new()
        }
    }
    return [System.Collections.Generic.HashSet[int]]::new()
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
        $galleryImages = $data.props.initialState.adView.data.gallery.images
        
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

try {
    # 2. Load processed ad_ids
    Write-Host "Loading processed ad_ids from $ProcessedAdsFile..." -ForegroundColor Cyan
    $processedAdIds = Get-ProcessedAdIds -FilePath $ProcessedAdsFile
    if ($null -ne $processedAdIds) {
        Write-Host "Found $($processedAdIds.Count) already processed ad_ids" -ForegroundColor Yellow
    } else {
        Write-Host "No processed ad_ids found (starting fresh)" -ForegroundColor Yellow
        $processedAdIds = [System.Collections.Generic.HashSet[int]]::new()
    }
    
    if ($IgnoreProcessed) {
        Write-Host "IgnoreProcessed flag is set to `$true - will reprocess all ads" -ForegroundColor Yellow
    }

    # 3. Fetch the listing page content
    Write-Host "Fetching listing page content..." -ForegroundColor Cyan
    try {
        $webResponse = Invoke-WebRequest -Uri $url -Headers $headers -UseBasicParsing
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

    # 4. Extract the JSON from the __NEXT_DATA__ script tag
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

    # 5. Parse JSON
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

    # 6. Access the ads list with null checks
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

    # 7. Filter ads based on processed list (unless IgnoreProcessed is true)
    if ($IgnoreProcessed) {
        $ads = $allAds
        if ($null -ne $ads) {
            Write-Host "Processing all $($ads.Count) advertisements (ignoring processed list)`n" -ForegroundColor Green
        } else {
            Write-Host "No ads found to process`n" -ForegroundColor Yellow
        }
    } else {
        if ($null -ne $allAds) {
            $ads = $allAds | Where-Object { 
                if ($null -eq $_ -or $null -eq $_.ad_id) { 
                    $false 
                } else { 
                    -not $processedAdIds.Contains($_.ad_id) 
                }
            }
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

    # 8. Display initial ad list
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

        # 9. Fetch details from each ad_link
        $results = @()
        $random = New-Object System.Random
        $newlyProcessedAdIds = [System.Collections.Generic.HashSet[int]]::new()
        
        for ($i = 0; $i -lt $ads.Count; $i++) {
            $ad = $ads[$i]
            if ($null -eq $ad) {
                Write-Warning "Ad at index $i is null, skipping..."
                continue
            }
            
            $adTitle = if ($null -ne $ad.subject) { $ad.subject } else { "Unknown" }
            $adId = if ($null -ne $ad.ad_id) { $ad.ad_id } else { "Unknown" }
            Write-Host "`n[$($i + 1)/$($ads.Count)] Processing: $adTitle (ID: $adId)" -ForegroundColor Cyan
            
            if ($null -eq $ad.ad_link -or [string]::IsNullOrWhiteSpace($ad.ad_link)) {
                Write-Warning "Ad link is null or empty for ad ID: $adId, skipping..."
                continue
            }
            
            # Random delay between 1-3 seconds (except for first request)
            $delay = if ($i -eq 0) { 0 } else { $random.Next(1, 3) }
            
            $adDetails = Get-AdDetails -AdLink $ad.ad_link -RequestHeaders $headers -DelaySeconds $delay
            
            $price = if ($null -ne $ad.price_byn) { $ad.price_byn / 100 } else { 0 }
            $region = if ($null -ne $ad.ad_parameters) { 
                ($ad.ad_parameters | Where-Object {$_.p -eq "area"} | Select-Object -ExpandProperty vl)
            } else { 
                $null 
            }
            
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
                Description = $cleanDescription
                ImageCount = if ($null -ne $adDetails -and $adDetails.Success -and $null -ne $adDetails.GalleryImages) { $adDetails.GalleryImages.Count } else { 0 }
                Images = if ($null -ne $adDetails -and $adDetails.Success -and $null -ne $adDetails.GalleryImages) { $adDetails.GalleryImages } else { @() }
                FetchSuccess = if ($null -ne $adDetails) { $adDetails.Success } else { $false }
            }
            
            $results += $result
            
            # Display summary for this ad
            if ($null -ne $adDetails -and $adDetails.Success) {
                $descLength = if ($null -ne $result.Description) { $result.Description.Length } else { 0 }
                Write-Host "  ✓ Description: $descLength characters" -ForegroundColor Green
                Write-Host "  ✓ Gallery Images: $($result.ImageCount)" -ForegroundColor Green
                # Mark as processed only if fetch was successful
                if ($null -ne $ad.ad_id) {
                    [void]$newlyProcessedAdIds.Add($ad.ad_id)
                    [void]$processedAdIds.Add($ad.ad_id)
                }
            } else {
                Write-Host "  ✗ Failed to fetch details" -ForegroundColor Red
            }
        }
        
        # 10. Save processed ad_ids to JSON file
        if ($newlyProcessedAdIds.Count -gt 0) {
            Write-Host "`nSaving $($newlyProcessedAdIds.Count) newly processed ad_ids..." -ForegroundColor Cyan
            Save-ProcessedAdIds -ProcessedAdIds $processedAdIds -FilePath $ProcessedAdsFile
        } else {
            Write-Host "`nNo new ads processed, skipping save." -ForegroundColor Yellow
        }
    } else {
        Write-Host "No new ads to process. All ads have already been processed." -ForegroundColor Yellow
        $results = @()
    }

    # 11. Display final results summary
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
        
        # 12. Display detailed results with descriptions and image URLs
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
    } else {
        Write-Host "`nNo results to display." -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Failed to retrieve or parse data: $_"
}