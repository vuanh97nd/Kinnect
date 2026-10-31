Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = 'Chon o / thu muc luu du lieu Kinnect'
$dialog.ShowNewFolderButton = $true
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
 [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
 [Console]::Write($dialog.SelectedPath)
}
$dialog.Dispose()
