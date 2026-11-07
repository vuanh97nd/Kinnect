param(
    [Parameter(Mandatory = $true)][string]$Message,
    [string]$ConversationId = 'b8e11388-823f-44c8-a8a2-cdbee0647980',
    [string]$RequestId = "",
    [switch]$DirectCli
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot

if ($DirectCli) {
    # Chế độ gọi CLI trực tiếp (Lưu ý: Tiêu tốn quota AI và chỉ hoạt động với phiên headless mới, không kết nối được phiên IDE)
    $agentCli = Join-Path $env:USERPROFILE '.gemini\bin\agy.exe'
    if (-not (Test-Path -LiteralPath $agentCli)) { throw 'Antigravity CLI not found.' }
    Push-Location -LiteralPath $projectRoot
    try {
        & $agentCli --conversation $ConversationId -p $Message --output-format json
        exit $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

# Chế độ mặc định: Hộp thư Mailbox 0-Quota kết nối trực tiếp phiên Antigravity IDE
Push-Location -LiteralPath $projectRoot
try {
    if (-not $RequestId) {
        $timestamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
        $RequestId = "req-codex-$timestamp"
    }
    
    $reqDir = Join-Path $projectRoot ".agent-mailbox\requests"
    $resDir = Join-Path $projectRoot ".agent-mailbox\responses"
    if (-not (Test-Path $reqDir)) { New-Item -ItemType Directory -Path $reqDir -Force | Out-Null }
    if (-not (Test-Path $resDir)) { New-Item -ItemType Directory -Path $resDir -Force | Out-Null }
    
    $nowIso = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $reqObj = [ordered]@{
        id = $RequestId
        sender = "codex"
        targetConversationId = $ConversationId
        prompt = $Message
        createdAt = $nowIso
        status = "pending"
    }
    $reqJson = $reqObj | ConvertTo-Json -Depth 5
    $reqFile = Join-Path $reqDir "$RequestId.json"
    [System.IO.File]::WriteAllText($reqFile, $reqJson, [System.Text.Encoding]::UTF8)

    # Khởi tạo trước file response trạng thái pending
    $resObj = [ordered]@{
        id = $RequestId
        conversationId = $ConversationId
        status = "pending"
        updatedAt = $nowIso
        ackAt = $null
        completedAt = $null
        summary = $null
        artifacts = @()
        error = $null
    }
    $resJson = $resObj | ConvertTo-Json -Depth 5
    $resFile = Join-Path $resDir "$RequestId.json"
    [System.IO.File]::WriteAllText($resFile, $resJson, [System.Text.Encoding]::UTF8)

    # Cập nhật con trỏ codex-session.json
    $sessionFile = Join-Path $projectRoot ".agent-mailbox\codex-session.json"
    $sessionObj = [ordered]@{
        project = "Kinnect"
        codexThreadId = "01a1b659-f0cf-7192-b581-65591fa047db"
        antigravityConversationId = $ConversationId
        pendingRequestId = $RequestId
        requestFile = ".agent-mailbox/requests/$RequestId.json"
        replyFile = ".agent-mailbox/responses/$RequestId.json"
        deliveryNote = "Yêu cầu đã được lưu an toàn vào Mailbox. Antigravity IDE (b8e11388-823f-44c8-a8a2-cdbee0647980) đọc và xử lý ngay khi user bấm hoặc gõ 'tiếp tục'."
    }
    $sessionObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sessionFile -Encoding UTF8

    Write-Host "[MAILBOX_DISPATCH_SUCCESS]" -ForegroundColor Green
    Write-Host "RequestId: $RequestId" -ForegroundColor Cyan
    Write-Host "TargetSession: $ConversationId (Active Antigravity IDE Session)" -ForegroundColor Cyan
    Write-Host "Saved to: $reqFile" -ForegroundColor Yellow
    Write-Host "Notice for Codex: Tin nhắn đã được lưu vào Mailbox an toàn (0 token consumed, không lo lỗi 429)." -ForegroundColor Green
    Write-Host "Hãy thông báo User gõ 'tiếp tục' ở Antigravity IDE để phiên IDE xử lý và trả kết quả về Codex!" -ForegroundColor Magenta
    exit 0
} catch {
    Write-Error $_
    exit 1
} finally {
    Pop-Location
}
