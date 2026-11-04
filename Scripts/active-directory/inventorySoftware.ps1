#requires -Version 5.1
<#
Inventario de software remoto por computador ou perfil de usuario.
Sem modulos externos, sem elevacao automatica, sem exportacao.
Requer WinRM e permissoes administrativas no computador de destino.
Perfis descarregados sao montados temporariamente no Registro e desmontados no finally.
Uso: .\Inventario_Remoto_Windows_v3.ps1 -Computador PC123
#>
param([string]$Computador)
$ErrorActionPreference = 'Stop'

function Resolve-Computador {
    param([string]$Nome)
    while ([string]::IsNullOrWhiteSpace($Nome)) { $Nome = Read-Host 'Nome logico, FQDN ou IP' }
    $Nome = $Nome.Trim()
    if ($Nome -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.:-]*$') { throw 'Nome de computador invalido.' }
    $candidatos = @($Nome)
    if ($Nome -notmatch '[.:]') {
        try {
            $s = Get-CimInstance Win32_ComputerSystem
            if ($s.PartOfDomain -and $s.Domain) { $candidatos += "$Nome.$($s.Domain)" }
        } catch { }
    }
    foreach ($c in ($candidatos | Select-Object -Unique)) {
        try { $null = [System.Net.Dns]::GetHostAddresses($c); return $c } catch { }
    }
    if ($Nome -notmatch '[.:]') {
        $dominio = (Read-Host 'Nome nao resolvido. Dominio DNS alternativo (ENTER para continuar sem dominio)').Trim()
        if ($dominio) {
            if ($dominio -notmatch '^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$') { throw 'Dominio DNS invalido.' }
            return "$Nome.$dominio"
        }
    }
    return $Nome
}

$Coletor = {
    param([ValidateSet('Perfis','Maquina','Usuario','Todos')][string]$Modo, [string]$SidAlvo)
    $ErrorActionPreference = 'Stop'
    $chaveUninstall = 'Software\Microsoft\Windows\CurrentVersion\Uninstall'
    $chaveWow = 'Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'

    function Ler-Programas {
        param([Microsoft.Win32.RegistryKey]$Raiz, [string[]]$Caminhos,
              [string]$Escopo, [string]$Usuario, [string]$SID)
        foreach ($caminho in $Caminhos) {
            $base = $null
            try {
                $base = $Raiz.OpenSubKey($caminho)
                if (-not $base) { continue }
                foreach ($subnome in $base.GetSubKeyNames()) {
                    $sub = $null
                    try {
                        $sub = $base.OpenSubKey($subnome)
                        if (-not $sub) { continue }
                        $nome = [string]$sub.GetValue('DisplayName', '')
                        if ([string]::IsNullOrWhiteSpace($nome)) { continue }
                        $kb = $sub.GetValue('EstimatedSize', $null)
                        $tamanho = $null
                        if ($null -ne $kb) {
                            try { $tamanho = [math]::Round(([double]$kb / 1024), 2) } catch { }
                        }
                        [PSCustomObject]@{
                            Nome = $nome
                            Versao = [string]$sub.GetValue('DisplayVersion', '')
                            Fabricante = [string]$sub.GetValue('Publisher', '')
                            DataRegistro = [string]$sub.GetValue('InstallDate', '')
                            TamanhoMB = $tamanho
                            Escopo = $Escopo
                            Usuario = $Usuario
                            SID = $SID
                            Chave = "$caminho\$subnome"
                        }
                    } catch {
                        Write-Warning "Registro inacessivel: $caminho\$subnome - $($_.Exception.Message)"
                    } finally { if ($sub) { $sub.Close() } }
                }
            } catch {
                Write-Warning "Falha ao consultar $caminho - $($_.Exception.Message)"
            } finally { if ($base) { $base.Close() } }
        }
    }

    $perfis = @(
        Get-CimInstance Win32_UserProfile -ErrorAction Stop |
            Where-Object { -not $_.Special -and $_.SID -match '^S-1-5-21-' } |
            Sort-Object LocalPath |
            ForEach-Object {
                $nome = $_.SID
                try {
                    $nome = ([System.Security.Principal.SecurityIdentifier]::new($_.SID)).Translate(
                        [System.Security.Principal.NTAccount]).Value
                } catch {
                    if ($_.LocalPath) { $nome = Split-Path $_.LocalPath -Leaf }
                }
                [PSCustomObject]@{
                    SID = $_.SID
                    Usuario = $nome
                    Perfil = $_.LocalPath
                    Carregado = [bool]$_.Loaded
                }
            }
    )
    if ($Modo -eq 'Perfis') { return $perfis }

    $resultados = @()
    if ($Modo -in @('Maquina','Todos')) {
        # Usa as visoes nativas do Registro para evitar duplicar WOW6432Node.
        foreach ($visao in @([Microsoft.Win32.RegistryView]::Registry64,
                             [Microsoft.Win32.RegistryView]::Registry32)) {
            $hklm = $null
            try {
                $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                    [Microsoft.Win32.RegistryHive]::LocalMachine, $visao)
                $resultados += @(Ler-Programas -Raiz $hklm -Caminhos @($chaveUninstall) `
                    -Escopo 'Computador' -Usuario 'Todos' -SID '')
            } finally { if ($hklm) { $hklm.Close() } }
        }
    }

    if ($Modo -in @('Usuario','Todos')) {
        $selecionados = @($perfis)
        if ($Modo -eq 'Usuario') {
            $selecionados = @($perfis | Where-Object { $_.SID -eq $SidAlvo })
            if ($selecionados.Count -ne 1) { throw 'Perfil selecionado nao encontrado.' }
        }
        foreach ($perfil in $selecionados) {
            $montagem = $null
            $montadoAqui = $false
            $sid = $perfil.SID
            $hku = $null
            try {
                $hku = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                    [Microsoft.Win32.RegistryHive]::Users,
                    [Microsoft.Win32.RegistryView]::Default)
                $raiz = $hku.OpenSubKey($sid)
                if ($raiz) { $raiz.Close(); $montagem = $sid }
                else {
                    $ntuser = Join-Path $perfil.Perfil 'NTUSER.DAT'
                    if (-not (Test-Path -LiteralPath $ntuser -PathType Leaf)) {
                        Write-Warning "Perfil sem NTUSER.DAT acessivel: $($perfil.Usuario)"
                        continue
                    }
                    $montagem = 'INV_SOFT_' + [guid]::NewGuid().ToString('N')
                    $out = & reg.exe load "HKU\$montagem" "$ntuser" 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "Nao foi possivel carregar perfil $($perfil.Usuario): $($out -join ' ')"
                        continue
                    }
                    $montadoAqui = $true
                }
                $raizUsuario = $null
                try {
                    $raizUsuario = $hku.OpenSubKey($montagem)
                    if (-not $raizUsuario) { throw 'Registro do perfil indisponivel.' }
                    $resultados += @(Ler-Programas -Raiz $raizUsuario `
                        -Caminhos @($chaveUninstall, $chaveWow) `
                        -Escopo 'Usuario' -Usuario $perfil.Usuario -SID $sid)
                } finally { if ($raizUsuario) { $raizUsuario.Close() } }
            } catch {
                Write-Warning "Falha no perfil $($perfil.Usuario): $($_.Exception.Message)"
            } finally {
                if ($hku) { $hku.Close() }
                if ($montadoAqui) {
                    [GC]::Collect()
                    [GC]::WaitForPendingFinalizers()
                    $out = & reg.exe unload "HKU\$montagem" 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning "ATENCAO: hive temporaria HKU\$montagem nao foi desmontada: $($out -join ' ')"
                    }
                }
            }
        }
    }
    return @($resultados | Sort-Object Escopo, Usuario, Nome, Versao, Chave -Unique)
}

try {
    $destino = Resolve-Computador $Computador
    Write-Host "`nDestino: $destino" -ForegroundColor Cyan
    # Test-WSMan pode falhar mesmo quando ICMP responde: nao usar ping como bloqueio.
    Test-WSMan -ComputerName $destino -ErrorAction Stop | Out-Null
    $sessao = New-PSSession -ComputerName $destino -ErrorAction Stop
    try {
        do {
            Write-Host "`n=== INVENTARIO DE SOFTWARES: $destino ===" -ForegroundColor Cyan
            Write-Host '1 - Softwares instalados para todos (computador + perfis)'
            Write-Host '2 - Softwares de um perfil especifico'
            Write-Host '3 - Softwares instalados no computador (todos os usuarios)'
            Write-Host '0 - Sair'
            $opcao = (Read-Host 'Escolha').Trim()
            if ($opcao -eq '0') { break }
            if ($opcao -notin @('1','2','3')) { Write-Warning 'Opcao invalida.'; continue }

            $modo = switch ($opcao) { '1' {'Todos'} '2' {'Usuario'} '3' {'Maquina'} }
            $sid = ''
            if ($opcao -eq '2') {
                $perfis = @(Invoke-Command -Session $sessao -ScriptBlock $Coletor -ArgumentList 'Perfis','' -ErrorAction Stop)
                if (-not $perfis.Count) { Write-Warning 'Nenhum perfil encontrado.'; continue }
                Write-Host "`nPerfis encontrados:" -ForegroundColor Yellow
                for ($i=0; $i -lt $perfis.Count; $i++) {
                    Write-Host ('{0,3} - {1} | {2} | {3}' -f ($i+1),$perfis[$i].Usuario,$perfis[$i].Perfil,$perfis[$i].SID)
                }
                $numero = 0
                $entrada = Read-Host 'Numero do perfil (ENTER cancela)'
                if (-not [int]::TryParse($entrada,[ref]$numero) -or $numero -lt 1 -or $numero -gt $perfis.Count) {
                    Write-Warning 'Selecao cancelada ou invalida.'
                    continue
                }
                $sid = $perfis[$numero-1].SID
            }
            Write-Host "`nConsultando Registro remoto..." -ForegroundColor Yellow
            $programas = @(Invoke-Command -Session $sessao -ScriptBlock $Coletor -ArgumentList $modo,$sid -ErrorAction Stop)
            Write-Host "Registros encontrados: $($programas.Count)" -ForegroundColor Green
            $filtro = Read-Host 'Filtrar pelo nome do software (ENTER lista todos)'
            if ($filtro) {
                $programas = @($programas | Where-Object { $_.Nome.IndexOf($filtro,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
            }
            if ($programas.Count) {
                $programas | Select-Object Nome,Versao,Fabricante,Escopo,Usuario,DataRegistro,TamanhoMB |
                    Format-Table -AutoSize -Wrap
            } else { Write-Warning 'Nenhum registro corresponde a consulta.' }
            Write-Host "Exibidos: $($programas.Count)" -ForegroundColor Cyan
        } while ($true)
    } finally { Remove-PSSession $sessao }
} catch {
    Write-Host "Falha: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Confira DNS, WinRM, firewall e permissoes administrativas remotas.'
}
