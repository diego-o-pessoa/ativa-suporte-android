# Ativa Suporte – instalação pelo WhatsApp (sem Google Play)

O app é enviado como arquivo `.apk`. No Brasil o Google exige duas coisas para
apps de fora da Play Store:

1. **Desenvolvedor verificado** (desde 30/09/2026): o app e os celulares ficam
   registrados no **Android Developer Console** (gratuito até 20 celulares).
2. **Play Protect**: bloqueia apps com Acessibilidade (o controle da tela)
   vindos do WhatsApp/navegador. Na instalação, a pessoa desliga o Play Protect.

---

## Parte 1 – Registro gratuito (uma vez, pelo T.I.)

Pré-requisito: os 4 segredos `ANDROID_KEYSTORE_*` cadastrados no GitHub
(Settings > Secrets and variables > Actions). Só o APK **sem** "-TESTE" no nome
serve: ele é assinado com a chave da Ativa, que é a registrada no Google.

1. Acesse <https://developer.android.com/developer-verification> e entre no
   **Android Developer Console** com uma conta Google com verificação em duas
   etapas. Escolha a conta de **distribuição limitada** (gratuita, até 20 celulares).
2. Registre o app:
   - **Nome do pacote:** `com.ativalocacao.suporte`
   - **Certificado de assinatura (SHA-256):**
     `F3:B6:0B:74:2E:8B:0D:5F:CE:D7:68:7D:A0:25:CB:2D:8C:FC:18:C6:54:C8:39:77:D1:C6:B7:C1:D4:5E:2D:EC`
3. Em **Dispositivos**, adicione cada celular (nome amigável, ex.: "Ana – Londrina")
   e envie ao celular o QR code/link de autorização que o console gerar.
   O limite de 20 vale para a conta inteira. Para mais celulares, a conta pode
   virar "distribuição completa" (US$ 25, uma vez) sem perder o que foi feito.

> Os nomes dos menus do console podem mudar; o fluxo é sempre: registrar o app
> (pacote + certificado) e autorizar cada celular.

---

## Parte 2 – Mensagem para o colaborador (copie e envie com o APK)

> **Ativa Suporte – app de ajuda do T.I.**
>
> 1. Toque no arquivo **ativa-suporte.apk** aqui no WhatsApp.
> 2. Se aparecer "Instalar apps desconhecidos": toque em **Configurações**,
>    ligue **Permitir desta fonte** e volte.
> 3. Se aparecer **"App bloqueado"** / **"Play Protect"**:
>    abra a **Play Store** → toque na sua **foto** (canto de cima) → **Play Protect**
>    → **engrenagem** → desligue **"Verificar apps com o Play Protect"**.
>    Volte ao WhatsApp e toque no arquivo de novo.
> 4. Toque em **Instalar** e depois em **Abrir**.
> 5. No app, toque nos **botões azuis**, um por vez. No passo
>    "Permitir o controle da tela", se aparecer **"Configuração restrita"**,
>    toque em **Apareceu "Configuração restrita"?** e siga as instruções.
> 6. Pronto! Quando precisar de ajuda, abra o **Ativa Suporte** e toque em
>    **PEDIR AJUDA AO T.I.**

Depois de instalado, o Play Protect pode ser religado. Teste no primeiro
celular: se ele avisar sobre o Ativa Suporte, deixe o Play Protect desligado
nesse aparelho.

---

## Alternativa: pelo cabo (T.I.)

`tools/instalar-por-cabo.cmd` instala pelo cabo USB a partir de um computador
com Windows (fica fora das duas regras) e já libera avisos, controle da tela e
bateria. Útil quando o T.I. tem o celular em mãos.
