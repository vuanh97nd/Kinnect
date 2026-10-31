param([Parameter(Mandatory=$true)][ValidatePattern('^[a-z0-9.-]+\.supabase\.com$')][string]$PoolerHost)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$destination = Join-Path $projectRoot 'chat-db.env'
if ([IO.File]::Exists($destination) -and ([IO.FileInfo]$destination).Length -gt 0) {
    Write-Host 'chat-db.env already exists; it was left unchanged.'
    exit 1
}
$securePassword = Read-Host 'Kinnect Chat database password (hidden)' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($password)) { throw 'Password is required.' }
    $encoded = [Uri]::EscapeDataString($password)
    $content = @"
# Configuration only; current SQLite backend does not load this file.
KINNECT_DATABASE_PROVIDER=postgres
KINNECT_DATABASE_URL=postgresql://postgres.mmxqhcngrejxyhhfirzo:${encoded}@${PoolerHost}:5432/postgres?sslmode=verify-full
KINNECT_DATABASE_CA_FILE=data/certificates/supabase-prod-ca-2021.crt
KINNECT_DATABASE_POOL_MAX=5
KINNECT_DATABASE_CONNECT_TIMEOUT_MS=10000
KINNECT_MEDIA_PROVIDER=local
"@
    # Apply a private ACL before writing any secret.
    # A previous failed ACL setup may have left an empty file. Never overwrite secrets.
    $stream = [IO.File]::Open($destination,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::None)
    if ($stream.Length -gt 0) { $stream.Close(); throw 'Configuration already contains data; left unchanged.' }
    $stream.Close()
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true,$false)
    $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')
    $acl.AddAccessRule($rule)
    # Use .NET directly: some Windows installations cannot load the Set-Acl module.
    if ([IO.File].GetMethods().Name -contains 'SetAccessControl') {
        [IO.File]::SetAccessControl($destination,$acl)
    } else {
        [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]::new($destination),$acl)
    }
    [IO.File]::WriteAllText($destination,$content,(New-Object Text.UTF8Encoding($false)))
    Write-Host 'Saved private connection configuration. No credentials were printed.' -ForegroundColor Green
    Write-Host 'This does not activate PostgreSQL or migrate production data.'
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $password = $null; $encoded = $null; $content = $null
    $securePassword.Dispose()
}
