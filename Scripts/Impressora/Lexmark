<#
.SYNOPSIS
  Corrige remotamente configuracoes do Lexmark ScanBack.
.EXAMPLE
  .\ScanBack-Correcao-v2.ps1 -NomeLogico PC123 -WhatIf
.EXAMPLE
  .\ScanBack-Correcao-v2.ps1 -NomeLogico PC123
.NOTES
  Executar com uma conta autorizada a administrar o computador remoto.
  O modo WhatIf nao altera firewall, processos ou registro.
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [Parameter(Position = 0)]
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$')]
    [string]$NomeLogico,

    [ValidatePattern('^[a-zA-Z0-9.-]+$')]
    [ValidatePattern('^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$')]
    [string]$Dominio,

    [string]$LogDirectory = "$env:ProgramData\ScanBack-Correcao\Logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $NomeLogico) {
    $NomeLogico = Read-Host 'Digite ou cole o nome logico do computador'
    if ($NomeLogico -notmatch '^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$') {
        throw 'Nome logico invalido.'
    }
}

# O parametro -Dominio tem prioridade. Caso omitido, consultar o dominio
# DNS ao qual o computador local pertence; nao confundir com WORKGROUP.
if ([string]::IsNullOrWhiteSpace($Dominio)) {
    try {
        $sistemaLocal = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($sistemaLocal.PartOfDomain -and
            $sistemaLocal.Domain -match '^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$') {
            $Dominio = $sistemaLocal.Domain
            Write-Host "Dominio local detectado: $Dominio" -ForegroundColor Green
        }
    }
    catch {
        Write-Warning "Falha ao detectar dominio local: $($_.Exception.Message)"
    }
}

while ([string]::IsNullOrWhiteSpace($Dominio)) {
    $resposta = (Read-Host 'Informe o dominio DNS do computador remoto (ex.: empresa.local)').Trim()
    if ($resposta -match '^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$') {
        $Dominio = $resposta
    }
    else {
        Write-Warning 'Informe um dominio DNS valido, com pelo menos um ponto.'
    }
}

$Computador = "$NomeLogico.$Dominio"
Write-Host "Destino remoto: $Computador" -ForegroundColor Cyan
$Simulacao = [bool]$WhatIfPreference
$LogFile = $null

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')][string]$Level = 'INFO'
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

$session = $null
try {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    $safeComputer = $NomeLogico -replace '[^a-zA-Z0-9-]', '_'
    $LogFile = Join-Path $LogDirectory ('ScanBack_{0}_{1}.log' -f $safeComputer, (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Write-Log "Inicio da verificacao: $Computador. Simulacao: $Simulacao"

    # Test-Connection nao e requisito: ICMP pode estar bloqueado.
    if (Test-Connection -ComputerName $Computador -Count 1 -Quiet -ErrorAction SilentlyContinue) {
        Write-Log 'ICMP respondeu.' 'OK'
    }
    else {
        Write-Log 'Sem resposta ICMP; tentando WinRM mesmo assim.' 'WARN'
    }

    # Validacao real da conectividade remota e da autorizacao.
    $session = New-PSSession -ComputerName $Computador -ErrorAction Stop
    Write-Log 'Sessao PowerShell Remoting estabelecida.' 'OK'

    $resultado = Invoke-Command -Session $session -ArgumentList $Simulacao -ScriptBlock {
        param([bool]$DryRun)
        $ErrorActionPreference = 'Stop'
        $events = New-Object 'System.Collections.Generic.List[string]'
        $issues = New-Object 'System.Collections.Generic.List[string]'
        $changed = 0

        function Add-Event([string]$Message) { $events.Add($Message) }
        function Add-Issue([string]$Message) { $issues.Add($Message) }

        $exe = 'C:\Program Files (x86)\Lexmark ScanBack Utility\scanwiz.exe'
        $ruleName = 'Scanback Utility'
        $profilesKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $sidPattern = '^S-1-5-21-\d+-\d+-\d+-\d+$'
        $loadedByScript = New-Object 'System.Collections.Generic.List[string]'

        try {
            # Etapa 1: processo
            try {
                $processes = @(Get-Process -Name scanwiz -ErrorAction SilentlyContinue)
                if ($processes.Count -gt 0) {
                    if ($DryRun) { Add-Event 'SIMULACAO: encerraria o processo scanwiz.' }
                    else {
                        $processes | Stop-Process -Force -ErrorAction Stop
                        $changed++
                        Add-Event 'Processo scanwiz encerrado.'
                    }
                }
                else { Add-Event 'Processo scanwiz nao estava em execucao.' }
            }
            catch { Add-Issue "Processo: $($_.Exception.Message)" }

            # Etapa 2: firewall. Recria apenas regras com o nome usado pelo script original.
            try {
                if (-not (Test-Path -LiteralPath $exe)) {
                    Add-Issue "Executavel nao encontrado: $exe. Firewall nao alterado."
                }
                else {
                    if ($DryRun) { Add-Event "SIMULACAO: recriaria regras TCP e UDP de entrada para $exe." }
                    else {
                        $existing = @(Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue)
                        if ($existing.Count -gt 0) {
                            $existing | Remove-NetFirewallRule -ErrorAction Stop
                        }
                        foreach ($protocol in @('TCP', 'UDP')) {
                            New-NetFirewallRule -DisplayName $ruleName -Direction Inbound `
                                -Action Allow -Program $exe -Protocol $protocol `
                                -Profile Any -Enabled True -ErrorAction Stop | Out-Null
                        }
                        $created = @(Get-NetFirewallRule -DisplayName $ruleName -ErrorAction Stop)
                        if ($created.Count -ne 2) { throw "Esperadas 2 regras, encontradas $($created.Count)." }
                        $changed++
                        Add-Event 'Regras de firewall TCP/UDP recriadas e verificadas.'
                    }
                }
            }
            catch { Add-Issue "Firewall: $($_.Exception.Message)" }

            # Etapa 3: perfis de usuario locais, inclusive nao carregados.
            try {
                $profiles = @(Get-ChildItem -Path $profilesKey -ErrorAction Stop |
                    Where-Object { $_.PSChildName -match $sidPattern } |
                    ForEach-Object {
                        $profile = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction Stop
                        [pscustomobject]@{
                            SID = $_.PSChildName
                            HiveFile = Join-Path ([Environment]::ExpandEnvironmentVariables($profile.ProfileImagePath)) 'NTUSER.DAT'
                        }
                    })

                foreach ($profile in $profiles) {
                    $sid = $profile.SID
                    $hivePath = "Registry::HKEY_USERS\$sid"
                    $wasLoaded = Test-Path -LiteralPath $hivePath
                    $loadedHere = $false
                    try {
                        if (-not $wasLoaded) {
                            if (-not (Test-Path -LiteralPath $profile.HiveFile)) {
                                Add-Issue "Perfil $sid sem NTUSER.DAT acessivel."
                                continue
                            }
                            if ($DryRun) {
                                Add-Event "SIMULACAO: carregaria $($profile.HiveFile) para verificar ScanBack de $sid."
                                continue
                            }
                            $output = & reg.exe load "HKU\$sid" "$($profile.HiveFile)" 2>&1
                            if ($LASTEXITCODE -ne 0) { throw "reg load falhou: $output" }
                            $loadedHere = $true
                            $loadedByScript.Add($sid)
                        }

                        $key = "Registry::HKEY_USERS\$sid\Software\Lexmark\ScanBack"
                        $backup = "Registry::HKEY_USERS\$sid\Software\Lexmark\ScanBack.old"
                        if (Test-Path -LiteralPath $key) {
                            if (Test-Path -LiteralPath $backup) {
                                Add-Issue "Perfil $sid: ScanBack.old ja existe; chave original preservada."
                            }
                            elseif ($DryRun) {
                                Add-Event "SIMULACAO: renomearia ScanBack para ScanBack.old em $sid."
                            }
                            else {
                                Rename-Item -LiteralPath $key -NewName 'ScanBack.old' -ErrorAction Stop
                                $changed++
                                Add-Event "Perfil $sid: ScanBack renomeado para ScanBack.old."
                            }
                        }
                        else { Add-Event "Perfil $sid: chave ScanBack ausente." }
                    }
                    catch { Add-Issue "Perfil ${sid}: $($_.Exception.Message)" }
                    finally {
                        if ($loadedHere) {
                            try {
                                [gc]::Collect()
                                [gc]::WaitForPendingFinalizers()
                                $output = & reg.exe unload "HKU\$sid" 2>&1
                                if ($LASTEXITCODE -ne 0) { throw "reg unload falhou: $output" }
                                [void]$loadedByScript.Remove($sid)
                            }
                            catch { Add-Issue "Falha ao descarregar hive ${sid}: $($_.Exception.Message)" }
                        }
                    }
                }
            }
            catch { Add-Issue "Enumeracao de perfis: $($_.Exception.Message)" }

            # Etapa 4: perfil .DEFAULT (nao e o perfil Default de novos usuarios).
            try {
                $defaultKey = 'Registry::HKEY_USERS\.DEFAULT\Software\Lexmark\Lexmark ScanBack Utility'
                $defaultBackup = 'Registry::HKEY_USERS\.DEFAULT\Software\Lexmark\Lexmark ScanBack Utility.old'
                if (Test-Path -LiteralPath $defaultKey) {
                    if (Test-Path -LiteralPath $defaultBackup) {
                        Add-Issue '.DEFAULT: backup .old ja existe; chave original preservada.'
                    }
                    elseif ($DryRun) { Add-Event 'SIMULACAO: renomearia chave do ScanBack em .DEFAULT.' }
                    else {
                        Rename-Item -LiteralPath $defaultKey -NewName 'Lexmark ScanBack Utility.old' -ErrorAction Stop
                        $changed++
                        Add-Event '.DEFAULT: chave renomeada para .old.'
                    }
                }
                else { Add-Event '.DEFAULT: chave do ScanBack ausente.' }
            }
            catch { Add-Issue ".DEFAULT: $($_.Exception.Message)" }
        }
        finally {
            # Tentativa adicional de liberar hives eventualmente pendentes.
            foreach ($sid in @($loadedByScript.ToArray())) {
                try {
                    [gc]::Collect()
                    [gc]::WaitForPendingFinalizers()
                    $output = & reg.exe unload "HKU\$sid" 2>&1
                    if ($LASTEXITCODE -ne 0) { throw "reg unload falhou: $output" }
                }
                catch { Add-Issue "Hive pendente ${sid}: $($_.Exception.Message)" }
            }
        }

        [pscustomobject]@{
            Computer = $env:COMPUTERNAME
            Simulated = $DryRun
            Changes = $changed
            Events = @($events.ToArray())
            Issues = @($issues.ToArray())
        }
    } -ErrorAction Stop

    foreach ($eventMessage in $resultado.Events) { Write-Log $eventMessage 'INFO' }
    foreach ($issue in $resultado.Issues) { Write-Log $issue 'WARN' }
    if ($resultado.Issues.Count -gt 0) {
        Write-Log "Concluido com $($resultado.Issues.Count) pendencia(s). Consulte o log." 'WARN'
    }
    elseif ($Simulacao) { Write-Log 'Simulacao concluida; nenhuma alteracao realizada.' 'OK' }
    else { Write-Log "Correcao concluida; $($resultado.Changes) grupo(s) de alteracoes." 'OK' }
}
catch {
    Write-Log "Falha geral: $($_.Exception.Message)" 'ERROR'
    throw
}
finally {
    if ($null -ne $session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
        Write-Log 'Sessao remota encerrada.'
    }
    if ($LogFile) { Write-Host "Log: $LogFile" }
}
