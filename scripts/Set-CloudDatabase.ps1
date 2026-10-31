$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $projectRoot 'cloud-db.env'
if (Test-Path -LiteralPath $destination) {
    Write-Host 'cloud-db.env already exists; it was left unchanged.'
    exit 1
}
$securePassword = Read-Host 'Supabase database password (hidden)' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($password)) { throw 'Password is required.' }
    $encoded = [Uri]::EscapeDataString($password)
    $content = @"
# Configuration only; current SQLite backend does not load this file.
KINNECT_DATABASE_PROVIDER=postgres
KINNECT_DATABASE_URL=postgresql://postgres.fetzoqpdxoaxfqqrcfci:${encoded}@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres?sslmode=verify-full
KINNECT_DATABASE_CA_FILE=
KINNECT_DATABASE_POOL_MAX=5
KINNECT_DATABASE_CONNECT_TIMEOUT_MS=10000
KINNECT_MEDIA_PROVIDER=local
"@
    # Apply a private ACL before writing any secret.
    $stream = [IO.File]::Open($destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    $stream.Close()
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true,$false)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $destination -AclObject $acl
    [IO.File]::WriteAllText($destination,$content,(New-Object Text.UTF8Encoding($false)))
    Write-Host 'Saved private connection configuration. No credentials were printed.' -ForegroundColor Green
    Write-Host 'This does not activate PostgreSQL or migrate production data.'
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $password = $null; $encoded = $null; $content = $null
    $securePassword.Dispose()
}
