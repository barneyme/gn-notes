#!/usr/bin/env pwsh
# gn.ps1 - Get Notes (PowerShell port)
# Zero-dependency PowerShell version of gn for Windows
# Syncs markdown notes via GitHub or Koofr WebDAV
# Author: Barney Matthews (ported from bash)
# Web: gn-notes.pages.dev | License: MIT

param(
    [switch]$h,
    [string]$d,
    [switch]$s,
    [switch]$c,
    [string]$r,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$NoteArgs
)

$NOTES_DIR = Join-Path $HOME "gn"
$CONFIG_FILE = Join-Path $NOTES_DIR "gn.conf"

# Ensure notes directory
if (-not (Test-Path $NOTES_DIR)) { New-Item -ItemType Directory -Path $NOTES_DIR -Force | Out-Null }

# --- Config loader ---
$gn_USER = $null; $gn_PASS = $null; $gn_PATH = $null; $gn_URL = $null
$GIT_TOKEN = $null; $GIT_OWNER = $null; $GIT_REPO = $null; $GIT_API = $null

if (Test-Path $CONFIG_FILE) {
    Get-Content $CONFIG_FILE | ForEach-Object {
        $line = $_.Trim()
        if (-not $line -or $line.StartsWith('#')) { return }
        $line = ($line -split '#')[0].Trim()
        if ($line -match '^\s*([^=]+)\s*=\s*(.*)$') {
            $key = $matches[1].Trim()
            $val = $matches[2].Trim()
            if ($val -match '^["''](.*)["'']$') { $val = $matches[1] }
            switch ($key) {
                'gn_USER' { $gn_USER = $val }
                'gn_PASS' { $gn_PASS = $val }
                'gn_PATH' { $gn_PATH = $val }
                'gn_URL' { $gn_URL = $val }
                'GIT_TOKEN' { $GIT_TOKEN = $val }
                'GIT_OWNER' { $GIT_OWNER = $val }
                'GIT_REPO' { $GIT_REPO = $val }
                'GIT_API' { $GIT_API = $val }
            }
        }
    }
}

# --- First-run setup ---
if (-not $gn_USER -and -not $GIT_TOKEN) {
    Write-Host "No config found at $CONFIG_FILE - let's set one up."
    Write-Host "Select your provider:"
    Write-Host "1) GitHub"
    Write-Host "2) Koofr"
    $choice = Read-Host "Choice [1-2]"
    switch ($choice) {
        '1' {
            $sec = Read-Host "GitHub Personal Access Token (input hidden)" -AsSecureString
            $GIT_TOKEN = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
            $GIT_OWNER = Read-Host "GitHub username (repo owner)"
            $GIT_REPO = Read-Host "Repository name"
        }
        default {
            $gn_URL = "https://app.koofr.net/dav/Koofr"
            $gn_USER = Read-Host "Koofr email/username"
            $sec = Read-Host "Koofr app password (input hidden)" -AsSecureString
            $gn_PASS = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
            $gn_PATH = Read-Host "Remote notes folder [/gn]"
            if (-not $gn_PATH) { $gn_PATH = "/gn" }
        }
    }
    $save = Read-Host "Save this config for future runs? [Y/n]"
    if ($save -notmatch '^[Nn]') {
        $lines = @()
        if ($GIT_TOKEN) {
            $lines += "GIT_TOKEN=$GIT_TOKEN"
            $lines += "GIT_OWNER=$GIT_OWNER"
            $lines += "GIT_REPO=$GIT_REPO"
        } else {
            $lines += "gn_URL=$gn_URL"
            $lines += "gn_USER=$gn_USER"
            $lines += "gn_PASS=$gn_PASS"
            $lines += "gn_PATH=$gn_PATH"
        }
        $lines | Set-Content -Path $CONFIG_FILE -Encoding UTF8
        Write-Host "Saved to $CONFIG_FILE"
    } else {
        Write-Host "Using credentials for this session only."
    }
}

# --- Detect engine ---
$SYNC_ENGINE = $null
if ($GIT_TOKEN -and $GIT_OWNER -and $GIT_REPO) {
    $SYNC_ENGINE = "GITHUB"
    if (-not $GIT_API) { $GIT_API = "https://api.github.com/repos/$GIT_OWNER/$GIT_REPO/contents" }
} elseif ($gn_USER -and $gn_PASS -and $gn_URL) {
    $SYNC_ENGINE = "KOOFR"
    $gn_URL = $gn_URL.TrimEnd('/')
    if (-not $gn_PATH) { $gn_PATH = "/notes" }
    $gn_PATH = "/" + $gn_PATH.TrimStart('/')
    if ($gn_PATH -eq "//") { $gn_PATH = "/" }
} else {
    Write-Error "Error: gn.conf is incomplete. Provide GitHub or Koofr credentials."
    exit 1
}

$EDITOR = if ($env:EDITOR) { $env:EDITOR } else { "notepad" }

function Show-Help {
    $remote = if ($SYNC_ENGINE -eq "GITHUB") { "GitHub: $GIT_OWNER/$GIT_REPO" } else { "Koofr: $gn_URL$gn_PATH" }
    @"
Usage: gn.ps1 [options] [note]

  -h Show this help
  -d NOTE Delete a note (local + remote)
  -r OLD NEW Rename a note (local + remote) - use: gn.ps1 -r old new
  -s Sync (pull) all remote notes down
  -c Clear saved credentials and reconfigure

Local commands (PowerShell):
  Get-ChildItem `$HOME\gn\*.md | Sort-Object LastWriteTime -Descending
  Select-String -Path `$HOME\gn\*.md -Pattern "term"
  Get-ChildItem `$HOME\gn -Recurse -Filter *.md | Where-Object LastWriteTime -gt (Get-Date).AddDays(-7)

Engine: $SYNC_ENGINE
Remote: $remote
Local: $NOTES_DIR
"@
    exit 0
}

function Get-KoofrCred {
    $sec = ConvertTo-SecureString $gn_PASS -AsPlainText -Force
    return New-Object System.Management.Automation.PSCredential($gn_USER, $sec)
}

function Invoke-Api {
    param($Method='GET', $Uri, $Headers=@{}, $Body=$null, $OutFile=$null)
    try {
        $params = @{ Method=$Method; Uri=$Uri; Headers=$Headers; UseBasicParsing=$true; ErrorAction='Stop' }
        if ($SYNC_ENGINE -eq 'KOOFR') { $params.Credential = Get-KoofrCred }
        if ($Body) { $params.Body = $Body }
        if ($OutFile) { $params.OutFile = $OutFile }
        if ($SYNC_ENGINE -eq 'GITHUB') { $params.Headers['User-Agent'] = 'gn-powershell' }
        return Invoke-WebRequest @params
    } catch {
        return $_.Exception.Response
    }
}

function Get-RemoteUrl {
    param($file)
    $enc = [System.Uri]::EscapeDataString($file).Replace('%2F','/')
    return "$gn_URL$gn_PATH/$enc"
}

function Get-FileHashSimple {
    param($path)
    if (Test-Path $path) { return (Get-FileHash $path -Algorithm MD5).Hash } else { return "" }
}

function Pull-Note {
    param($file)
    $localPath = Join-Path $NOTES_DIR $file
    $dir = Split-Path $localPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    if ($SYNC_ENGINE -eq 'GITHUB') {
        $url = "$GIT_API/$([System.Uri]::EscapeDataString($file).Replace('%2F','/'))"
        $headers = @{ Authorization = "Bearer $GIT_TOKEN" }
        try {
            $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method GET -UserAgent 'gn-powershell'
            $content = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($resp.content))
            Set-Content -Path $localPath -Value $content -NoNewline -Encoding UTF8
        } catch {
            if ($_.Exception.Response.StatusCode -eq 404) { Remove-Item $localPath -Force -ErrorAction SilentlyContinue }
        }
    } else {
        $url = Get-RemoteUrl $file
        $tmp = "$localPath.tmp"
        $r = Invoke-Api -Method GET -Uri $url -OutFile $tmp
        if ($r.StatusCode -eq 200) { Move-Item $tmp $localPath -Force }
        elseif ($r.StatusCode -eq 404) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue; Remove-Item $localPath -Force -ErrorAction SilentlyContinue }
        else { Remove-Item $tmp -Force -ErrorAction SilentlyContinue; Write-Error "Pull failed"; exit 1 }
    }
}

function Push-Note {
    param($file)
    $localPath = Join-Path $NOTES_DIR $file
    if ($SYNC_ENGINE -eq 'GITHUB') {
        $url = "$GIT_API/$([System.Uri]::EscapeDataString($file).Replace('%2F','/'))"
        $headers = @{ Authorization = "Bearer $GIT_TOKEN"; 'Content-Type'='application/json' }
        $content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($localPath))
        $msg = "gn: update $file $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $sha = $null
        try { $existing = Invoke-RestMethod -Uri $url -Headers @{Authorization="Bearer $GIT_TOKEN"} -UserAgent 'gn-powershell'; $sha = $existing.sha } catch {}
        $body = @{ message=$msg; content=$content }
        if ($sha) { $body.sha = $sha }
        $json = $body | ConvertTo-Json -Compress
        $r = Invoke-RestMethod -Uri $url -Method PUT -Headers $headers -Body $json -UserAgent 'gn-powershell'
    } else {
        $dir = Split-Path $file -Parent
        if ($dir -and $dir -ne '.') { Invoke-Api -Method MKCOL -Uri (Get-RemoteUrl $dir) | Out-Null }
        $url = Get-RemoteUrl $file
        $r = Invoke-Api -Method PUT -Uri $url -Body ([IO.File]::ReadAllBytes($localPath))
        if ($r.StatusCode -notin 200,201,204) { Write-Error "Push failed"; exit 1 }
    }
}

function Remove-Remote {
    param($file, $msg)
    if (-not $msg) { $msg = "gn: delete $file" }
    if ($SYNC_ENGINE -eq 'GITHUB') {
        $url = "$GIT_API/$([System.Uri]::EscapeDataString($file).Replace('%2F','/'))"
        try {
            $existing = Invoke-RestMethod -Uri $url -Headers @{Authorization="Bearer $GIT_TOKEN"} -UserAgent 'gn-powershell'
            $body = @{ message=$msg; sha=$existing.sha } | ConvertTo-Json
            Invoke-RestMethod -Uri $url -Method DELETE -Headers @{Authorization="Bearer $GIT_TOKEN";'Content-Type'='application/json'} -Body $body -UserAgent 'gn-powershell' | Out-Null
        } catch {}
    } else {
        $url = Get-RemoteUrl $file
        Invoke-Api -Method DELETE -Uri $url | Out-Null
    }
}

function Rename-Remote {
    param($old,$new)
    if ($SYNC_ENGINE -eq 'GITHUB') {
        Copy-Item (Join-Path $NOTES_DIR $old) (Join-Path $NOTES_DIR $new) -Force
        Push-Note $new
        Remove-Remote $old "gn: rename $old to $new"
        Remove-Item (Join-Path $NOTES_DIR $new) -Force -ErrorAction SilentlyContinue
    } else {
        $src = Get-RemoteUrl $old
        $dst = Get-RemoteUrl $new
        $headers = @{ Destination = $dst; Overwrite = 'F' }
        Invoke-Api -Method MOVE -Uri $src -Headers $headers | Out-Null
    }
}

function Sync-All {
    Write-Host "Syncing paths... [$SYNC_ENGINE]"
    if ($SYNC_ENGINE -eq 'GITHUB') {
        $headers = @{ Authorization = "Bearer $GIT_TOKEN" }
        $items = Invoke-RestMethod -Uri $GIT_API -Headers $headers -UserAgent 'gn-powershell'
        $items | Where-Object { $_.name -like '*.md' -and $_.type -eq 'file' } | ForEach-Object {
            Pull-Note $_.name
        }
    } else {
        $url = "$gn_URL$gn_PATH/"
        $cred = Get-KoofrCred
        $r = Invoke-WebRequest -Uri $url -Method PROPFIND -Headers @{ Depth='infinity' } -Credential $cred -UseBasicParsing
        ([xml]$r.Content).SelectNodes('//*[local-name()="href"]') | ForEach-Object {
            $href = [System.Uri]::UnescapeDataString($_.InnerText)
            if ($href -match [regex]::Escape($gn_PATH) + '/(.+\.md)$') {
                $rel = $matches[1]
                Pull-Note $rel
            }
        }
    }
    Write-Host "Sync complete."
    exit 0
}

# --- Handle switches ---
if ($h) { Show-Help }
if ($c) { Remove-Item $CONFIG_FILE -Force -ErrorAction SilentlyContinue; Write-Host "Config cleared."; exit 0 }
if ($d) {
    $file = $d; if ($file -notmatch '\.md$') { $file += '.md' }
    $path = Join-Path $NOTES_DIR $file
    if (-not (Test-Path $path)) { Write-Error "Error: '$file' not found."; exit 1 }
    $confirm = Read-Host "Delete '$file'? [y/N]"
    if ($confirm -match '^[Yy]') { Remove-Remote $file; Remove-Item $path -Force; Write-Host "Deleted." }
    exit 0
}
if ($r) {
    $old = $r; $new = $NoteArgs[0]
    if (-not $new) { Write-Error "Usage: -r OLD NEW"; exit 1 }
    if ($old -notmatch '\.md$') { $old += '.md' }
    if ($new -notmatch '\.md$') { $new += '.md' }
    Rename-Remote $old $new
    Move-Item (Join-Path $NOTES_DIR $old) (Join-Path $NOTES_DIR $new) -Force
    Write-Host "Renamed."
    exit 0
}
if ($s) { Sync-All }

# --- Main edit flow ---
$NOTE_NAME = if ($NoteArgs.Count -gt 0) { $NoteArgs[0] } else { "note" }
if ($NOTE_NAME -match '\.\.' -or $NOTE_NAME -eq 'gn.conf') { exit 1 }
if ($NOTE_NAME -notmatch '\.md$') { $NOTE_NAME += '.md' }

Set-Location $NOTES_DIR
$dir = Split-Path $NOTE_NAME -Parent
if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

Pull-Note $NOTE_NAME
$pre = Get-FileHashSimple $NOTE_NAME

# Launch editor
Start-Process -FilePath $EDITOR -ArgumentList "`"$NOTE_NAME`"" -Wait

if (Test-Path $NOTE_NAME) {
    $post = Get-FileHashSimple $NOTE_NAME
    if ($pre -ne $post) { Push-Note $NOTE_NAME }
}