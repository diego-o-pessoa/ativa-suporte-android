<#
  Ativa Suporte - instalacao pelo cabo USB (uso do T.I., no Windows).

  Por que pelo cabo: no Brasil o Google bloqueia (Play Protect) apps com
  Acessibilidade instalados fora da Play Store pelo navegador, WhatsApp ou
  gerenciador de arquivos, e exige desenvolvedor verificado. A instalacao
  pelo cabo (ADB) fica fora dessas regras.

  De quebra, libera pelo cabo o que o colaborador teria que liberar no
  assistente: avisos, controle da tela (Acessibilidade) e bateria.

  Uso: clique duas vezes em "instalar-por-cabo.cmd" (o .apk na mesma pasta),
  ou: powershell -ExecutionPolicy Bypass -File instalar-por-cabo.ps1 -Apk C:\caminho\app.apk
#>
param([string]$Apk = "")

$ErrorActionPreference = "Stop"
$Package = "com.ativalocacao.suporte"
$Service = "$Package/com.carriez.flutter_hbb.InputService"

function Step($text) { Write-Host ""; Write-Host "==> $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host ""; Write-Host "ERRO: $text" -ForegroundColor Red; Read-Host "Enter para sair"; exit 1 }

# --- APK ---------------------------------------------------------------
if (-not $Apk) {
    $found = Get-ChildItem -Path $PSScriptRoot -Filter "*.apk" -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $found) { Fail "Coloque o arquivo .apk do Ativa Suporte na mesma pasta deste script." }
    $Apk = $found.FullName
}
if (-not (Test-Path -LiteralPath $Apk)) { Fail "Arquivo nao encontrado: $Apk" }
Step "Aplicativo: $Apk"

# --- ADB (platform-tools oficial do Google) ----------------------------
$adb = (Get-Command adb.exe -ErrorAction SilentlyContinue).Source
if (-not $adb) {
    $tools = Join-Path $env:LOCALAPPDATA "AtivaSuporte\platform-tools"
    $adb = Join-Path $tools "adb.exe"
    if (-not (Test-Path $adb)) {
        Step "Baixando as ferramentas do Android (so na primeira vez)..."
        $zip = Join-Path $env:TEMP "platform-tools.zip"
        Invoke-WebRequest -UseBasicParsing -Uri "https://dl.google.com/android/repository/platform-tools-latest-windows.zip" -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath (Split-Path $tools) -Force
        Remove-Item $zip -Force
    }
}
function Adb { & $adb @args 2>&1 }

# --- Celular conectado e autorizado ------------------------------------
Step "Prepare o celular:"
Write-Host "  1. Configuracoes > Sobre o telefone > Informacoes do software:"
Write-Host "     toque 7 vezes em 'Numero de compilacao' (libera as Opcoes do desenvolvedor)."
Write-Host "  2. Configuracoes > Opcoes do desenvolvedor: ligue 'Depuracao USB'."
Write-Host "  3. Samsung: se existir, desligue 'Bloqueador automatico'"
Write-Host "     (Configuracoes > Seguranca e privacidade) - ele bloqueia o cabo."
Write-Host "  4. Ligue o cabo e, no celular, toque em 'Permitir' na pergunta de depuracao USB."
Adb start-server | Out-Null
$deadline = (Get-Date).AddMinutes(5)
while ($true) {
    $lines = (Adb devices) | Select-Object -Skip 1 | Where-Object { $_ -match "\S" }
    if ($lines | Where-Object { $_ -match "\sdevice$" }) { break }
    if ((Get-Date) -gt $deadline) { Fail "Nenhum celular autorizado em 5 minutos. Confira o cabo e a pergunta no celular." }
    $state = if ($lines -match "unauthorized") { "aguardando o 'Permitir' no celular" } else { "aguardando o celular" }
    Write-Host "  ...$state" -ForegroundColor DarkGray
    Start-Sleep -Seconds 3
}
$model = (Adb shell getprop ro.product.model) -join ""
$sdk = [int]((Adb shell getprop ro.build.version.sdk) -join "")
Step "Celular conectado: $model (Android SDK $sdk)"

# --- Instalacao ---------------------------------------------------------
Step "Instalando o Ativa Suporte..."
$out = (Adb install -r -g "$Apk") -join "`n"
if ($out -match "INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
    Write-Host "  Ja existe uma versao assinada com outra chave (versao de TESTE). Removendo e instalando de novo..."
    Adb uninstall $Package | Out-Null
    $out = (Adb install -r -g "$Apk") -join "`n"
}
if ($out -notmatch "Success") { Fail "A instalacao falhou:`n$out" }
Write-Host "  Instalado." -ForegroundColor Green

# --- Permissoes que o cabo consegue liberar ----------------------------
Step "Liberando as permissoes..."
# Avisos (Android 13+): o -g ja concede; reforca.
if ($sdk -ge 33) { Adb shell pm grant $Package android.permission.POST_NOTIFICATIONS | Out-Null }
# Controle da tela: liga o servico de Acessibilidade sem desligar os que ja existem.
$current = ((Adb shell settings get secure enabled_accessibility_services) -join "").Trim()
if ($current -eq "null" -or -not $current) { $current = "" }
if ($current -notmatch [regex]::Escape($Service)) {
    $value = if ($current) { "$current`:$Service" } else { $Service }
    Adb shell settings put secure enabled_accessibility_services "'$value'" | Out-Null
}
Adb shell settings put secure accessibility_enabled 1 | Out-Null
# Bateria: o app nao e encerrado com a tela apagada.
Adb shell dumpsys deviceidle whitelist "+$Package" | Out-Null
# Compartilhamento de tela: em alguns Android (ate o 13) dispensa o "Comecar agora".
Adb shell appops set $Package PROJECT_MEDIA allow | Out-Null

$enabled = ((Adb shell settings get secure enabled_accessibility_services) -join "")
if ($enabled -match [regex]::Escape($Service)) {
    Write-Host "  Controle da tela: liberado." -ForegroundColor Green
} else {
    Write-Host "  Controle da tela: NAO liberado pelo cabo. O colaborador faz o passo 2 do assistente." -ForegroundColor Yellow
}

# --- Abre o app ---------------------------------------------------------
Adb shell monkey -p $Package -c android.intent.category.LAUNCHER 1 | Out-Null
Step "Pronto! O Ativa Suporte abriu no celular."
Write-Host "  - Leia o QR code do GLPI em 'Cadastrar no GLPI (T.I.)' (Ativa Remote > Configuracoes)."
Write-Host "  - Depois, se quiser, desligue a 'Depuracao USB' nas Opcoes do desenvolvedor."
Read-Host "Enter para sair"
