# ============================================================
# GERENCIAMENTO REMOTO DO SPOOLER
# Detecta dominio, configura recuperacao e reinicia o servico.
# Requer permissoes administrativas no computador remoto.
# ============================================================

$ErrorActionPreference = "Stop"

function Get-DominioLocal {
    try {
        $sistema = Get-CimInstance -ClassName Win32_ComputerSystem

        if ($sistema.PartOfDomain -and
            -not [string]::IsNullOrWhiteSpace($sistema.Domain)) {

            return $sistema.Domain.Trim()
        }
    }
    catch {
        Write-Warning "Nao foi possivel detectar o dominio local."
    }

    return $null
}

# 1. Identificar o dominio automaticamente
$dominio = Get-DominioLocal

if ($dominio) {
    Write-Host "Dominio detectado: $dominio" -ForegroundColor Cyan
}
else {
    do {
        $dominio = (Read-Host "Informe o dominio DNS (ex: empresa.local)").Trim()

        if ($dominio -and $dominio -notmatch '^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$') {
            Write-Warning "Informe um dominio DNS valido."
            $dominio = $null
        }
    } until ($dominio)
}

# 2. Solicitar o computador
do {
    $nomeLogico = (Read-Host "Digite ou cole o nome logico do computador").Trim()

    if ($nomeLogico -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]*$') {
        Write-Warning "Nome de computador invalido."
        $nomeLogico = $null
    }
} until ($nomeLogico)

# 3. Montar o destino
# Se ja for FQDN, nao acrescenta o dominio.
if ($nomeLogico.Contains(".")) {
    $computador = $nomeLogico
}
else {
    $computador = "$nomeLogico.$dominio"
}

Write-Host ""
Write-Host "Computador: $computador" -ForegroundColor Cyan
Write-Host "Verificando acesso remoto..." -ForegroundColor Yellow

# 4. Testar PowerShell Remoting
try {
    Test-WSMan -ComputerName $computador -ErrorAction Stop | Out-Null
}
catch {
    Write-Host "ERRO: PowerShell Remoting indisponivel em $computador." -ForegroundColor Red
    Write-Host "Verifique DNS, rede, firewall e WinRM."
    return
}

# 5. Executar configuracao remota
try {
    $resultado = Invoke-Command -ComputerName $computador -ErrorAction Stop -ScriptBlock {

        $ErrorActionPreference = "Stop"
        $serviceName = "Spooler"

        # Verificar se o servico existe
        $servico = Get-Service -Name $serviceName -ErrorAction Stop

        # Configurar recuperacao automatica:
        # 1a falha: reiniciar imediatamente
        # 2a falha: reiniciar imediatamente
        # 3a falha: reiniciar imediatamente
        # reset= 0: nao zerar automaticamente a contagem
        $saida = & sc.exe failure $serviceName reset= 0 actions= restart/0/restart/0/restart/0 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao configurar recuperacao: $saida"
        }

        # Reiniciar o Spooler
        Restart-Service -Name $serviceName -Force -ErrorAction Stop

        # Aguardar ate 15 segundos pelo estado Running
        $limite = (Get-Date).AddSeconds(15)

        do {
            Start-Sleep -Seconds 1
            $servico = Get-Service -Name $serviceName
        }
        while ($servico.Status -ne "Running" -and
               (Get-Date) -lt $limite)

        # Retornar resultado
        [PSCustomObject]@{
            Computador = $env:COMPUTERNAME
            Servico = $serviceName
            Status = $servico.Status.ToString()
            Recuperacao = "Configurada"
            Sucesso = ($servico.Status -eq "Running")
        }
    }

    # 6. Exibir resultado
    Write-Host ""
    Write-Host "========== RESULTADO ==========" -ForegroundColor Cyan

    $resultado | Format-List Computador, Servico, Status, Recuperacao

    if ($resultado.Sucesso) {
        Write-Host "Spooler reiniciado com sucesso!" -ForegroundColor Green
    }
    else {
        Write-Warning "O Spooler nao atingiu o estado Running."
    }
}
catch {
    Write-Host ""
    Write-Host "ERRO NA EXECUCAO REMOTA:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
