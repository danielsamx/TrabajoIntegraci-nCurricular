# Emisor de ejemplo para Windows PowerShell / Example emitter for Windows PowerShell
#
#   .\emitter.ps1 "A320,D180"
#   .\emitter.ps1 P -Url http://192.168.1.50:8000
#   .\emitter.ps1 -Interactive
#
# Si PowerShell bloquea el script / If PowerShell blocks the script:
#   powershell -ExecutionPolicy Bypass -File .\emitter.ps1 C

param(
    [Parameter(Position = 0)] [string] $Line,
    [string] $Url = "http://localhost:8000",
    [switch] $Interactive
)

function Send-HandCommand([string] $Command) {
    $body = @{ command = $Command } | ConvertTo-Json -Compress
    try {
        $r = Invoke-RestMethod -Method Post -Uri "$Url/api/command" -ContentType "application/json" -Body $body
        $extra = if ($r.gesture) { $r.gesture.name } elseif ($r.action) { $r.action } else { "" }
        Write-Host ("OK   {0,-24} {1,-14} {2,5} ms" -f $Command, $extra, $r.pose.duration_ms) -ForegroundColor Cyan
    }
    catch {
        # ES: 422 = rechazado; el cuerpo trae etapa, código y motivo.
        # EN: 422 = rejected; the body carries stage, code and reason.
        $detail = $_.ErrorDetails.Message
        if ($detail) {
            $e = $detail | ConvertFrom-Json
            Write-Host ("FAIL {0,-24} {1}/{2}: {3}" -f $Command, $e.stage, $e.code, $e.message) -ForegroundColor Yellow
        } else {
            Write-Host ("FAIL {0}: {1}" -f $Command, $_.Exception.Message) -ForegroundColor Yellow
        }
    }
}

if ($Line) { Send-HandCommand $Line }

if ($Interactive) {
    Write-Host "Escribe una línea y Enter (vacío para salir) / Type a line and Enter (empty to quit)"
    while ($true) {
        $l = Read-Host ">"
        if ([string]::IsNullOrWhiteSpace($l)) { break }
        Send-HandCommand $l.Trim()
    }
}
