param(
    [string]$NomeLogico
)

# ============================================================
# GERENCIADOR DE SESSOES REMOTAS - WINDOWS
# Consulta, identifica e permite encerrar sessoes.
# Sem dominio fixo.
# ============================================================

$ErrorActionPreference = "Stop"

function Write-Status {
    param(
        [string]$Mensagem,
        [string]$Cor = "White"
    )

    Write-Host $Mensagem -ForegroundColor $Cor
}

function Get-SessoesRemotas {
    param([string]$Computador)

    # O QWINSTA retorna sessoes do Windows.
    $saida = @(& qwinsta.exe "/server:$Computador" 2>&1)
    $codigo = $LASTEXITCODE

    if ($codigo -ne 0) {
        throw "Falha no QWINSTA ($codigo): $($saida -join ' ')"
    }

    if ($saida.Count -lt 2) {
        return @()
    }

    # Identifica as colunas pelo cabecalho.
    $cabecalho = [string]$saida[0]

    $posUsuario = $cabecalho.IndexOf("USERNAME")
    $posID = $cabecalho.IndexOf("ID", $posUsuario + 8)
    $posEstado = $cabecalho.IndexOf("STATE", $posID + 2)

    if ($posUsuario -lt 0 -or
        $posID -lt 0 -or
        $posEstado -lt 0) {
        throw "Formato de cabecalho QWINSTA nao reconhecido."
    }

    $sessoes = foreach ($linhaOriginal in ($saida | Select-Object -Skip 1)) {

        $linha = [string]$linhaOriginal

        if ([string]::IsNullOrWhiteSpace($linha)) {
            continue
        }

        # Remove indicador da sessao atual.
        $linha = $linha.TrimStart('>', ' ')

        # Garante comprimento minimo.
        $linha = $linha.PadRight($posEstado + 20)

        $sessao = $linha.Substring(
            0, $posUsuario
        ).Trim()

        $usuario = $linha.Substring(
            $posUsuario, $posID - $posUsuario
        ).Trim()

        $idTexto = $linha.Substring(
            $posID, $posEstado - $posID
        ).Trim()

        $estado = $linha.Substring(
            $posEstado
        ).Trim().Split(' ')[0]

        # Ignora linhas sem ID numerico.
        if ($idTexto -notmatch '^\d+$') {
            continue
        }

        [PSCustomObject]@{
            Usuario = $usuario
            Sessao = $sessao
            ID = [int]$idTexto
            Estado = $estado
            Tipo = if ($sessao -match '^rdp') {
                "RDP"
            }
            elseif ($sessao -eq "console") {
                "Console"
            }
            else {
                "Outro"
            }
        }
    }

    return @($sessoes)
}

function Write-Auditoria {
    param(
        [string]$Computador,
        [string]$Usuario,
        [int]$ID,
        [string]$Resultado
    )

    $diretorio = Join-Path $env:LOCALAPPDATA "GerenciadorSessoes"
    $arquivo = Join-Path $diretorio "auditoria.csv"

    if (-not (Test-Path $diretorio)) {
        New-Item -ItemType Directory -Path $diretorio -Force |
            Out-Null
    }

    [PSCustomObject]@{
        Data = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Operador = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        Computador = $Computador
        Usuario = $Usuario
        SessaoID = $ID
        Resultado = $Resultado
    } | Export-Csv -Path $arquivo -Append `
        -NoTypeInformation -Encoding UTF8
}

# ============================================================
# 1. IDENTIFICACAO DO COMPUTADOR
# ============================================================

if ([string]::IsNullOrWhiteSpace($NomeLogico)) {
    $NomeLogico = Read-Host "Digite o nome logico do computador"
}

$NomeLogico = $NomeLogico.Trim()

if ($NomeLogico -notmatch '^[a-zA-Z0-9][a-zA-Z0-9.-]*$') {
    Write-Status "Nome logico invalido." "Red"
    return
}

Write-Host ""
Write-Status "============================================" "Cyan"
Write-Status " GERENCIADOR DE SESSOES REMOTAS" "Cyan"
Write-Status "============================================" "Cyan"
Write-Host "Computador: $NomeLogico"
Write-Host "Operador: $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Host "Data: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')"

# ============================================================
# 2. DIAGNOSTICO DE REDE
# ============================================================

Write-Host ""
Write-Status "[1] DIAGNOSTICO DE CONECTIVIDADE" "Yellow"

try {
    $ips = [System.Net.Dns]::GetHostAddresses($NomeLogico)

    Write-Status "DNS: Resolvido" "Green"

    foreach ($ip in $ips) {
        Write-Host "IP: $($ip.IPAddressToString)"
    }
}
catch {
    Write-Status "DNS: Nao resolvido" "Yellow"
}

try {
    $ping = Test-Connection -ComputerName $NomeLogico `
        -Count 1 -Quiet -ErrorAction Stop

    if ($ping) {
        Write-Status "ICMP: Respondendo" "Green"
    }
    else {
        Write-Status "ICMP: Sem resposta" "Yellow"
    }
}
catch {
    Write-Status "ICMP: Teste indisponivel" "Yellow"
}

try {
    $tcp = Test-NetConnection -ComputerName $NomeLogico `
        -Port 3389 -InformationLevel Quiet `
        -WarningAction SilentlyContinue

    if ($tcp) {
        Write-Status "RDP TCP/3389: Acessivel" "Green"
    }
    else {
        Write-Status "RDP TCP/3389: Indisponivel" "Yellow"
    }
}
catch {
    Write-Status "RDP TCP/3389: Nao foi possivel testar" "Yellow"
}

# ============================================================
# 3. CONSULTA DAS SESSOES
# ============================================================

Write-Host ""
Write-Status "[2] CONSULTANDO SESSOES..." "Yellow"

try {
    $sessoes = @(Get-SessoesRemotas -Computador $NomeLogico)
}
catch {
    Write-Status "Falha ao consultar sessoes remotas." "Red"
    Write-Host $_.Exception.Message
    return
}

# Considera apenas sessoes com usuario.
$usuarios = @(
    $sessoes | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.Usuario)
    }
)

Write-Host ""
Write-Status "[3] USUARIOS IDENTIFICADOS" "Cyan"

if ($usuarios.Count -eq 0) {
    Write-Status "Nenhuma sessao com usuario identificada." "Yellow"
    return
}

$usuarios |
    Sort-Object ID |
    Format-Table Usuario, Sessao, ID, Estado, Tipo -AutoSize

# ============================================================
# 4. RESUMO
# ============================================================

Write-Host ""
Write-Status "[4] RESUMO DAS SESSOES" "Cyan"

$ativas = @(
    $usuarios | Where-Object {
        $_.Estado -match '^(Active|Ativo)$'
    }
)

$desconectadas = @(
    $usuarios | Where-Object {
        $_.Estado -match '^(Disc|Desconectado)$'
    }
)

Write-Host "Total de sessoes com usuario: $($usuarios.Count)"
Write-Host "Sessoes ativas: $($ativas.Count)"
Write-Host "Sessoes desconectadas: $($desconectadas.Count)"

# ============================================================
# 5. PERGUNTAR SOBRE ENCERRAMENTO
# ============================================================

Write-Host ""
$resposta = Read-Host "Deseja encerrar alguma sessao? (S/N)"

if ($resposta -notmatch '^(S|SIM)$') {
    Write-Status "Nenhuma sessao foi encerrada." "Green"
    return
}

$idDigitado = Read-Host "Digite o ID da sessao que deseja encerrar"

$idSelecionado = 0

if (-not [int]::TryParse($idDigitado, [ref]$idSelecionado)) {
    Write-Status "ID invalido." "Red"
    return
}

$selecionada = $usuarios |
    Where-Object { $_.ID -eq $idSelecionado } |
    Select-Object -First 1

if (-not $selecionada) {
    Write-Status "ID nao encontrado na lista de usuarios." "Red"
    return
}

# ============================================================
# 6. CONFIRMACAO DE SEGURANCA
# ============================================================

Write-Host ""
Write-Status "ATENCAO: ENCERRAMENTO DE SESSAO" "Red"

Write-Host "Computador: $NomeLogico"
Write-Host "Usuario: $($selecionada.Usuario)"
Write-Host "Sessao: $($selecionada.Sessao)"
Write-Host "ID: $($selecionada.ID)"
Write-Host "Estado: $($selecionada.Estado)"

Write-Host ""
Write-Status "Trabalhos nao salvos podem ser perdidos." "Yellow"

$confirmacao = Read-Host "Digite ENCERRAR para confirmar"

if ($confirmacao -cne "ENCERRAR") {
    Write-Status "Operacao cancelada." "Yellow"
    return
}

# ============================================================
# 7. ENCERRAMENTO E VALIDACAO
# ============================================================

try {
    # Reconsulta para reduzir o risco de utilizar um ID antigo.
    $atuais = @(Get-SessoesRemotas -Computador $NomeLogico)

    $atual = $atuais |
        Where-Object {
            $_.ID -eq $selecionada.ID -and
            $_.Usuario -eq $selecionada.Usuario -and
            $_.Sessao -eq $selecionada.Sessao
        } |
        Select-Object -First 1

    if (-not $atual) {
        throw "A sessao mudou ou nao existe mais. Operacao cancelada."
    }

    Write-Status "Encerrando sessao..." "Yellow"

    $saidaLogoff = @(
        & logoff.exe $selecionada.ID "/server:$NomeLogico" 2>&1
    )

    if ($LASTEXITCODE -ne 0) {
        throw "LOGOFF falhou: $($saidaLogoff -join ' ')"
    }

    Start-Sleep -Seconds 2

    $sessoesDepois = @(
        Get-SessoesRemotas -Computador $NomeLogico
    )

    $permanece = @(
        $sessoesDepois | Where-Object {
            $_.ID -eq $selecionada.ID -and
            $_.Usuario -eq $selecionada.Usuario -and
            $_.Sessao -eq $selecionada.Sessao
        }
    )

    if ($permanece.Count -eq 0) {
        Write-Status "Sessao encerrada e ausencia confirmada." "Green"

        Write-Auditoria -Computador $NomeLogico `
            -Usuario $selecionada.Usuario `
            -ID $selecionada.ID `
            -Resultado "Encerramento confirmado"
    }
    else {
        Write-Status "Logoff enviado, mas a sessao ainda aparece." "Yellow"

        Write-Auditoria -Computador $NomeLogico `
            -Usuario $selecionada.Usuario `
            -ID $selecionada.ID `
            -Resultado "Validacao pendente"
    }
}
catch {
    Write-Status "Erro no encerramento: $($_.Exception.Message)" "Red"

    Write-Auditoria -Computador $NomeLogico `
        -Usuario $selecionada.Usuario `
        -ID $selecionada.ID `
        -Resultado "Falha: $($_.Exception.Message)"
}

Write-Host ""
Write-Status "========== FIM DA OPERACAO ==========" "Cyan"
