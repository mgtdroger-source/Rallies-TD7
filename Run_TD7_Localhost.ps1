param(
  [int]$Port = 8768
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path

function Get-ContentType([string]$path) {
  switch ([IO.Path]::GetExtension($path).ToLowerInvariant()) {
    ".html" { "text/html; charset=utf-8" }
    ".htm"  { "text/html; charset=utf-8" }
    ".js"   { "application/javascript; charset=utf-8" }
    ".mjs"  { "application/javascript; charset=utf-8" }
    ".css"  { "text/css; charset=utf-8" }
    ".json" { "application/json; charset=utf-8" }
    ".txt"  { "text/plain; charset=utf-8" }
    ".csv"  { "text/csv; charset=utf-8" }
    ".xml"  { "application/xml; charset=utf-8" }
    ".png"  { "image/png" }
    ".jpg"  { "image/jpeg" }
    ".jpeg" { "image/jpeg" }
    ".gif"  { "image/gif" }
    ".webp" { "image/webp" }
    ".svg"  { "image/svg+xml" }
    ".ico"  { "image/x-icon" }
    ".woff" { "font/woff" }
    ".woff2"{ "font/woff2" }
    default { "application/octet-stream" }
  }
}

$listener = [System.Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)

try {
  $listener.Start()
} catch {
  # Another TD7 localhost server may already own the fixed port.
  exit 0
}

while ($true) {
  $client = $listener.AcceptTcpClient()
  try {
    $stream = $client.GetStream()
    $reader = New-Object IO.StreamReader($stream, [Text.Encoding]::ASCII, $false, 4096, $true)

    $requestLine = $reader.ReadLine()
    if ([string]::IsNullOrWhiteSpace($requestLine)) {
      $client.Close()
      continue
    }

    while ($true) {
      $line = $reader.ReadLine()
      if ([string]::IsNullOrEmpty($line)) { break }
    }

    $parts = $requestLine.Split(" ")
    $rawPath = if ($parts.Count -ge 2) { $parts[1] } else { "/" }
    $requestPath = [Uri]::UnescapeDataString(($rawPath.Split("?")[0]))

    if ($requestPath -eq "/__td7_health") {
      $body = [Text.Encoding]::UTF8.GetBytes("TD7 localhost OK")
      $header = "HTTP/1.1 200 OK`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nCache-Control: no-store`r`nConnection: close`r`n`r`n"
      $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
      $stream.Write($headerBytes, 0, $headerBytes.Length)
      $stream.Write($body, 0, $body.Length)
      $stream.Flush()
      continue
    }

    $requestPath = $requestPath.TrimStart("/")
    if ([string]::IsNullOrWhiteSpace($requestPath)) { $requestPath = "index.html" }

    $candidate = [IO.Path]::GetFullPath((Join-Path $root $requestPath))
    $rootFull = [IO.Path]::GetFullPath($root + [IO.Path]::DirectorySeparatorChar)

    if (-not $candidate.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      $body = [Text.Encoding]::UTF8.GetBytes("404 Not Found")
      $header = "HTTP/1.1 404 Not Found`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($body.Length)`r`nConnection: close`r`n`r`n"
    } else {
      $body = [IO.File]::ReadAllBytes($candidate)
      $contentType = Get-ContentType $candidate
      $header = "HTTP/1.1 200 OK`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nCache-Control: no-cache`r`nConnection: close`r`n`r`n"
    }

    $headerBytes = [Text.Encoding]::ASCII.GetBytes($header)
    $stream.Write($headerBytes, 0, $headerBytes.Length)
    $stream.Write($body, 0, $body.Length)
    $stream.Flush()
  } catch {
    # Keep the local server alive if the browser closes a request early.
  } finally {
    try { $client.Close() } catch {}
  }
}
