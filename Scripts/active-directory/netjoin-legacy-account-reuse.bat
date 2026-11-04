
$dominio = "empresa.local"
$nomeLogico = Read-Host "Digite o nome lógico do computador"
$computador = "$nomeLogico.$dominio"

try {
    $softwares = Invoke-Command -ComputerName $computador -ErrorAction Stop -ScriptBlock {
        $caminhos = @(
            "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
            "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
            "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
        )

        Get-ItemProperty -Path $caminhos -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName } |
            Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
            Sort-Object DisplayName
    }

    $softwares | Format-Table -AutoSize

    $exportar = Read-Host "Deseja exportar para CSV? (S/N)"

    if ($exportar -eq "S") {
        $arquivo = Join-Path $PWD "softwares-$nomeLogico.csv"

        $softwares |
            Export-Csv -Path $arquivo -NoTypeInformation -Encoding UTF8

        Write-Host "Inventário exportado para: $arquivo"
    }
}
catch {
    Write-Error "Falha ao consultar $computador : $($_.Exception.Message)"
}
