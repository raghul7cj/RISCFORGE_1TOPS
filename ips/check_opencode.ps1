try {
    $sessions = Invoke-RestMethod -Uri "http://127.0.0.1:4096/session" -Method Get
    Write-Host "Active Sessions Count: $($sessions.Count)"
    foreach ($s in $sessions) {
        Write-Host "Session: $($s.id) | Title: $($s.title) | Model: $($s.model.id)"
    }
    
    $targetSession = "ses_f03542eb0ffeGDRqyoPtiwluVG"
    Write-Host "`n--- Messages for $targetSession ---"
    $msgs = Invoke-RestMethod -Uri "http://127.0.0.1:4096/session/$targetSession/message" -Method Get
    Write-Host "Total Messages: $($msgs.Count)"
    foreach ($m in $msgs) {
        Write-Host "`n[Message $($m.info.id)] Role: $($m.info.role) Finish: $($m.info.finish)"
        foreach ($p in $m.parts) {
            if ($p.type -eq "text" -and $p.text) {
                Write-Host "TEXT: $($p.text)"
            } elseif ($p.type -eq "tool") {
                Write-Host "TOOL: $($p.tool) [Status: $($p.state.status)]"
                if ($p.state.input.command) {
                    Write-Host "  CMD: $($p.state.input.command)"
                }
                if ($p.state.output) {
                    $outPreview = $p.state.output
                    if ($outPreview.Length -gt 400) {
                        $outPreview = $outPreview.Substring(0, 400) + "..."
                    }
                    Write-Host "  OUT: $outPreview"
                }
            }
        }
    }
} catch {
    Write-Host "Error connecting to OpenCode: $_"
}

