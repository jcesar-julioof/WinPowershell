# Windows — PowerShell e Scripts de Suporte

Repositório de comandos e scripts utilizados em atividades de suporte técnico, administração de sistemas Windows, diagnóstico remoto e automação de tarefas operacionais.

## 1. Configuração do ambiente

### Adicionar scripts às variáveis de ambiente

Para executar scripts e ferramentas diretamente pelo terminal, sem precisar informar o caminho completo, adicione o diretório às variáveis de ambiente do Windows.

**Diretório de exemplo:**

`C:\Scripts\Suporte`

**Procedimento:**

1. Acesse as configurações avançadas do sistema.
2. Selecione **Variáveis de Ambiente**.
3. Localize a variável `Path`.
4. Adicione o diretório `C:\Scripts\Suporte`.
5. Reinicie o terminal para aplicar a alteração.

**Observação:** adicionar um diretório ao `Path` não altera a política de execução do PowerShell. Scripts `.ps1` podem exigir configuração ou autorização adicional.

---

## 2. Identificação do equipamento

### Consultar número de série (BIOS)

**PowerShell:**

```powershell
Get-CimInstance Win32_BIOS | Select-Object SerialNumber
```

**CMD (legado):**

```cmd
wmic bios get serialnumber
```

**Descrição:** identifica o número de série informado pelo fabricante, auxiliando no inventário, abertura de chamados, controle patrimonial e atendimento de garantia.

**Observação:** o WMIC é uma ferramenta legada e pode não estar disponível em versões recentes do Windows. Recomenda-se utilizar PowerShell com CIM.

---

## 3. Administração remota

### Iniciar uma sessão remota PowerShell

```powershell
Enter-PSSession -ComputerName "computador.dominio.local"
```

**Descrição:** estabelece uma sessão interativa com um computador remoto para execução de comandos administrativos.

**Requisitos:**
- PowerShell Remoting (WinRM) configurado.
- Conectividade de rede e regras de firewall adequadas.
- Credenciais com permissões necessárias.

**Encerrar sessão:**

```powershell
Exit-PSSession
```

---

## 4. Envio de mensagens para usuários

### Enviar mensagem local

```cmd
msg * "Mensagem de suporte técnico"
```

**Descrição:** envia uma mensagem para sessões de usuários acessíveis no computador local.

### Enviar mensagem para computador remoto

```powershell
$nomeLogico = Read-Host "Digite o nome lógico do computador"
$mensagem = Read-Host "Informe a mensagem a ser enviada"

msg /server:$nomeLogico /time:300 * "$mensagem"
```

**Descrição:** solicita o nome do equipamento e a mensagem, permitindo enviar notificações aos usuários de sessões remotas acessíveis.

**Aplicações:**
- Avisos de manutenção programada.
- Solicitação de encerramento de aplicativos.
- Comunicação de indisponibilidade temporária.
- Orientações durante atendimentos técnicos.

**Observação:** o comando depende de permissões, conectividade e sessões acessíveis. O parâmetro `/time` define o tempo de exibição em segundos.

---

## 5. Scripts de suporte técnico

### 5.1. Configuração de reutilização de conta no domínio

**Arquivo:** `netjoin-legacy-account-reuse.bat`

**Descrição:** configura a chave `NetJoinLegacyAccountReuse` no Registro do Windows, relacionada ao comportamento legado de reutilização de contas de computadores durante operações de ingresso no domínio Active Directory.

**Atenção:** essa configuração pode reduzir proteções de segurança e não deve ser aplicada indiscriminadamente. Sua utilização depende da versão do Windows, das políticas de segurança e da validação da equipe responsável pelo Active Directory.

**Link:** [Visualizar script](./scripts/active-directory/netjoin-legacy-account-reuse.bat)

### 5.2. Inventário remoto de softwares instalados

**Arquivo:** `inventario-softwares.ps1`

**Descrição:** consulta remotamente os programas registrados como instalados em um computador Windows, retornando informações como nome, versão, fabricante e data de instalação, quando disponíveis.

**Aplicações:**
- Inventário de softwares.
- Auditoria de aplicativos instalados.
- Identificação de versões desatualizadas.
- Diagnóstico de incompatibilidades.
- Apoio à gestão de ativos de TI.

**Requisitos:** PowerShell Remoting habilitado, conectividade com o equipamento e permissões adequadas.

**Link:** [Visualizar script](./scripts/inventario/inventario-softwares.ps1)

---

## 6. Boas práticas

- Executar scripts administrativos somente em equipamentos autorizados.
- Validar o impacto antes de alterar configurações do sistema.
- Utilizar o princípio do menor privilégio.
- Evitar armazenar senhas diretamente no código.
- Registrar alterações relevantes para rastreabilidade.
- Testar scripts em ambiente controlado antes de utilizá-los em produção.
- Documentar requisitos, parâmetros e resultados esperados.
