// Ativa Suporte: tela unica do app para o colaborador.
//
// 1. Primeira vez: assistente com as permissoes, um botao grande por passo
//    (avanca sozinho quando o Android confirma).
// 2. Pronto: botao "PEDIR AJUDA AO T.I.". Ele liga o compartilhamento de
//    tela (o Android pede "Comecar agora" toda vez - regra do sistema) e
//    mostra o codigo e a senha (fixa deste celular) em letras grandes, com
//    envio pelo WhatsApp.
// 3. Com o T.I. conectado, a tela muda (fundo verde, sem codigo e senha) e
//    tem o botao "PARAR COMPARTILHAMENTO"; ao parar, volta ao codigo e senha.
// 4. Com o GLPI ao alcance (rede da empresa/VPN), o celular tambem aparece
//    no Ativa Remote e o T.I. pode pedir o acesso por la.

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_code_scanner/qr_code_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common.dart';
import '../consts.dart';
import '../mobile/pages/home_page.dart';
import '../models/platform_model.dart';
import '../models/server_model.dart';
import 'glpi_client.dart';

const kAtivaBlue = Color(0xFF15559F);
const kAtivaGreen = Color(0xFF48AE3E);
const kAtivaInk = Color(0xFF142A5B);

/// Senha fixa deste celular (o RustDesk guarda so o hash da senha
/// permanente; aqui fica a copia para mostrar na tela).
const _kFixedPasswordKey = 'ativa-fixed-password';

class AtivaHomePage extends StatefulWidget {
  const AtivaHomePage({Key? key}) : super(key: key);

  @override
  State<AtivaHomePage> createState() => _AtivaHomePageState();
}

class _AtivaHomePageState extends State<AtivaHomePage> with WidgetsBindingObserver {
  Timer? _permTimer;
  Timer? _glpiTimer;
  bool _notificationOk = true;
  bool _batteryOk = false;
  bool _helpActive = false;
  bool _starting = false;
  String _id = '';
  String _password = '';
  String _appVersion = '1.0.0';
  String _glpiStatus = '';
  Map<String, dynamic>? _pendingResult;
  bool _consentOpen = false;

  ServerModel get _server => gFFI.serverModel;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _server.addListener(_onServerChanged);
    _configureRustDesk();
    PackageInfo.fromPlatform().then((info) {
      final match = RegExp(r'^\d+\.\d+\.\d+').firstMatch(info.version);
      if (match != null) {
        _appVersion = match.group(0)!;
      }
    });
    _refresh();
    _permTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _scheduleGlpi(const Duration(seconds: 2));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _server.removeListener(_onServerChanged);
    _permTimer?.cancel();
    _glpiTimer?.cancel();
    _techGoneTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou das configuracoes do Android: confere as permissoes na hora.
    if (state == AppLifecycleState.resumed) {
      _refresh().then((_) => _continueGuide());
    }
  }

  void _onServerChanged() {
    _watchTechLeaving();
    // O compartilhamento parou por fora (notificacao, sistema): encerra a ajuda.
    if (_helpActive && !_starting && !_server.isStart) {
      setState(() => _helpActive = false);
    } else if (mounted) {
      setState(() {});
    }
  }

  /// Senha fixa de 8 caracteres, sorteada uma vez por celular, e entrada
  /// pela senha OU pelo botao "Aceitar" no celular (quando o T.I. conecta
  /// sem digitar a senha).
  Future<void> _configureRustDesk() async {
    await bind.mainSetOption(key: kOptionApproveMode, value: defaultOptionApproveMode);
    await bind.mainSetLocalOption(key: kOptionDisableFloatingWindow, value: 'Y');
    var password = bind.mainGetLocalOption(key: _kFixedPasswordKey);
    final created = password.isEmpty;
    if (created) {
      password = _newPassword();
      await bind.mainSetLocalOption(key: _kFixedPasswordKey, value: password);
    }
    if (created || await bind.mainGetCommon(key: 'permanent-password-set') != 'true') {
      final saved = await bind.mainSetPermanentPasswordWithResult(password: password);
      if (!saved && await bind.mainGetCommon(key: 'permanent-password-set') != 'true') {
        // Nao gravou: segue com a senha temporaria (a tela mostra ela) e
        // tenta de novo na proxima abertura.
        await bind.mainSetLocalOption(key: _kFixedPasswordKey, value: '');
        await bind.mainSetOption(key: kOptionVerificationMethod, value: kUseTemporaryPassword);
        _refresh();
        return;
      }
    }
    await bind.mainSetOption(key: kOptionVerificationMethod, value: kUsePermanentPassword);
    if (mounted) setState(() => _password = password);
  }

  /// 8 caracteres sem os que confundem ao ditar (0/O, 1/l/I).
  static String _newPassword() {
    const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    gFFI.invokeMethod('check_service');
    final notification = androidVersion < 33 || await AndroidPermissionManager.check(kAndroid13Notification);
    final battery = await AndroidPermissionManager.check(kRequestIgnoreBatteryOptimizations);
    final id = await bind.mainGetMyId();
    var password = bind.mainGetLocalOption(key: _kFixedPasswordKey);
    if (password.isEmpty) password = await bind.mainGetTemporaryPassword();
    if (!mounted) return;
    setState(() {
      _notificationOk = notification;
      _batteryOk = battery;
      _id = id;
      if (password.isNotEmpty) _password = password;
    });
  }

  bool get _inputOk => _server.inputOk;

  /// O T.I. esta conectado e vendo a tela agora.
  bool get _techConnected => _server.isStart && _server.clients.any((c) => c.authorized && !c.disconnected);
  bool get _ready => _notificationOk && _inputOk && _batteryOk;

  // ------------------------------------------------------------ permissoes

  Future<void> _askNotification() async {
    await AndroidPermissionManager.request(kAndroid13Notification);
    _refresh();
  }

  Future<void> _askBattery() async {
    await AndroidPermissionManager.request(kRequestIgnoreBatteryOptimizations);
    _refresh();
  }

  Future<void> _askAccessibility() async {
    // Aviso exigido pela Google Play antes de pedir a Acessibilidade: o que
    // ela acessa, para que e consentimento explicito ("Concordo").
    final go = await _explain(
      icon: Icons.touch_app,
      title: 'Permitir o controle da tela',
      lines: const [
        'O Ativa Suporte usa a Acessibilidade do Android só para o T.I. da Ativa '
            'tocar e digitar no seu celular durante um atendimento que você pediu ou autorizou.',
        'O app não lê, não guarda e não envia nada da sua tela fora do atendimento, '
            'e você pode encerrar a qualquer momento.',
      ],
      button: 'CONCORDO',
      cancel: 'NÃO CONCORDO',
    );
    if (!go) return;
    if (await _restrictedState() == 1) {
      // App instalado pelo WhatsApp/navegador: antes precisa liberar.
      await _startUnlockGuide();
      return;
    }
    await _showEnableSteps();
  }

  // Roteiro da "Configuracao restrita" (Android 13+). O Android nao deixa o
  // app se liberar sozinho; o app abre cada tela na hora certa:
  //  1. Acessibilidade: tocar em "Ativa Suporte" (o Android mostra o aviso
  //     de bloqueio - so depois disso aparecem os tres pontinhos).
  //  2. Informacoes do app: tres pontinhos > Permitir configuracoes restritas.
  //  3. Acessibilidade de novo: ligar a chave.
  int _guideStep = 0;
  bool _guideBusy = false;

  /// 1 = travada, 0 = liberada, -1 = nao deu para saber.
  Future<int> _restrictedState() async {
    if (androidVersion < 33) return 0;
    try {
      return await platformFFI.invokeMethodWithResult<int>('ativa_restricted_state') ?? -1;
    } catch (_) {
      return -1;
    }
  }

  Future<void> _showEnableSteps() async {
    final go = await _explain(
      icon: Icons.touch_app,
      title: 'Ligar o controle da tela',
      lines: const [
        '1. Toque em ABRIR.',
        '2. Toque em "Aplicativos instalados" (ou "Serviços baixados").',
        '3. Toque em "Ativa Suporte".',
        '4. Ligue a chave e toque em "Permitir".',
        '5. Volte para este aplicativo.',
      ],
      button: 'ABRIR',
    );
    if (!go) return;
    _guideStep = 3;
    AndroidPermissionManager.startAction(kActionAccessibilitySettings);
  }

  Future<void> _startUnlockGuide() async {
    final go = await _explain(
      icon: Icons.lock_open,
      title: 'Liberar o Ativa Suporte',
      lines: const [
        'O Android trava esta permissão em apps instalados pelo WhatsApp. Vamos liberar, o app abre cada tela para você.',
        'Primeiro passo:',
        '1. Toque em ABRIR.',
        '2. Toque em "Aplicativos instalados" (ou "Serviços baixados") e depois em "Ativa Suporte".',
        '3. Vai aparecer "Configuração restrita". Toque em OK.',
        '4. Volte para este aplicativo.',
      ],
      button: 'ABRIR',
    );
    if (!go) return;
    _guideStep = 1;
    AndroidPermissionManager.startAction(kActionAccessibilitySettings);
  }

  /// Chamado ao voltar das configuracoes do Android: mostra o proximo passo.
  Future<void> _continueGuide() async {
    if (_guideStep == 0 || _guideBusy || !mounted) return;
    _guideBusy = true;
    try {
      // O estado da Acessibilidade chega do Android logo depois de voltar.
      await Future.delayed(const Duration(milliseconds: 800));
      gFFI.invokeMethod('check_service');
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted || _inputOk) {
        _guideStep = 0;
        return;
      }
      final restricted = await _restrictedState();
      switch (_guideStep) {
        case 1:
          if (restricted == 0) {
            _guideStep = 0;
            await _showEnableSteps();
            return;
          }
          final go = await _explain(
            icon: Icons.lock_open,
            title: 'Agora, liberar',
            lines: const [
              '1. Toque em ABRIR.',
              '2. Toque nos três pontinhos (⋮) no canto de cima.',
              '3. Toque em "Permitir configurações restritas" e confirme.',
              '4. Volte para este aplicativo.',
            ],
            button: 'ABRIR',
          );
          _guideStep = go ? 2 : 0;
          if (go) AndroidPermissionManager.startAction('android.settings.APPLICATION_DETAILS_SETTINGS');
          break;
        case 2:
          if (restricted == 1) {
            final again = await _explain(
              icon: Icons.lock,
              title: 'Ainda está travado',
              lines: const [
                'Os três pontinhos só aparecem depois de tocar em "Ativa Suporte" na tela de Acessibilidade.',
                'Vamos repetir: toque em ABRIR, toque em "Ativa Suporte", toque em OK no aviso e volte para cá.',
              ],
              button: 'ABRIR',
            );
            _guideStep = again ? 1 : 0;
            if (again) AndroidPermissionManager.startAction(kActionAccessibilitySettings);
          } else {
            _guideStep = 0;
            await _showEnableSteps();
          }
          break;
        default:
          // Tentou ligar a chave e voltou sem conseguir: se o Android travou
          // ("Configuracao restrita"), os tres pontinhos ja estao liberados.
          _guideStep = 0;
          if (restricted == 0 || androidVersion < 33) return;
          final go = await _explain(
            icon: Icons.lock_open,
            title: 'Apareceu "Configuração restrita"?',
            lines: const [
              'Então vamos liberar:',
              '1. Toque em ABRIR.',
              '2. Toque nos três pontinhos (⋮) no canto de cima.',
              '3. Toque em "Permitir configurações restritas" e confirme.',
              '4. Volte para este aplicativo.',
            ],
            button: 'ABRIR',
            cancel: 'NÃO APARECEU',
          );
          if (go) {
            _guideStep = 2;
            AndroidPermissionManager.startAction('android.settings.APPLICATION_DETAILS_SETTINGS');
          }
      }
    } finally {
      _guideBusy = false;
    }
  }

  /// Link "Apareceu Configuracao restrita?" do passo 2.
  Future<void> _unlockRestricted() => _startUnlockGuide();

  // ------------------------------------------------------------ ajuda

  /// Liga o compartilhamento de tela. true quando o Android liberou.
  Future<bool> _startSharing() async {
    if (_server.isStart && _server.mediaOk) {
      return true;
    }
    final go = await _explain(
      icon: Icons.screen_share,
      title: 'Compartilhar a tela com o T.I.',
      lines: const [
        'O Android vai perguntar se pode compartilhar a tela.',
        'Toque em "COMEÇAR AGORA".',
      ],
      button: 'CONTINUAR',
    );
    if (!go) return false;
    setState(() => _starting = true);
    try {
      await _server.startService();
      // Espera o "Comecar agora" (ate 60 s).
      for (var i = 0; i < 120 && !_server.mediaOk; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        gFFI.invokeMethod('check_service');
      }
      if (!_server.mediaOk) {
        await _server.stopService();
        _toast('O compartilhamento não foi liberado. Tente de novo e toque em "Começar agora".');
        return false;
      }
      return true;
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _stopSharing() async {
    if (_server.isStart) {
      // Derruba o T.I. e desliga o compartilhamento.
      await _server.stopService();
    }
    _refresh();
  }

  Future<void> _requestHelp() async {
    if (!await _startSharing()) return;
    setState(() => _helpActive = true);
    await _refresh();
    _scheduleGlpi(Duration.zero);
  }

  /// O T.I. ja entrou neste atendimento.
  bool _techWasHere = false;
  Timer? _techGoneTimer;

  /// O T.I. saiu do RustDesk: para o compartilhamento no celular. Espera
  /// alguns segundos porque o RustDesk do computador reconecta sozinho
  /// quando a internet oscila.
  void _watchTechLeaving() {
    if (_techConnected) {
      _techWasHere = true;
      _techGoneTimer?.cancel();
      _techGoneTimer = null;
    } else if (_techWasHere && _server.isStart && _techGoneTimer == null) {
      _techGoneTimer = Timer(const Duration(seconds: 5), () async {
        _techGoneTimer = null;
        if (!mounted || _techConnected || !_server.isStart) return;
        await _endHelp();
        _toast('O T.I. saiu. O compartilhamento da tela foi encerrado.');
      });
    }
  }

  Future<void> _endHelp() async {
    _techWasHere = false;
    _techGoneTimer?.cancel();
    _techGoneTimer = null;
    setState(() => _helpActive = false);
    await _stopSharing();
    _scheduleGlpi(Duration.zero);
  }

  void _sendWhatsApp() {
    final text = 'Preciso de suporte no celular.\nCódigo: ${_formatId(_id)}\nSenha: $_password';
    launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}'), mode: LaunchMode.externalApplication);
  }

  // ------------------------------------------------------------ GLPI

  void _scheduleGlpi(Duration delay) {
    _glpiTimer?.cancel();
    _glpiTimer = Timer(delay, _glpiCycle);
  }

  Future<void> _glpiCycle() async {
    if (!GlpiClient.configured) {
      _scheduleGlpi(const Duration(seconds: 30));
      return;
    }
    var next = 30;
    try {
      final sharing = _server.isStart && _server.mediaOk;
      final result = _pendingResult;
      final response = await GlpiClient.report(
        rustdeskId: _id,
        ready: _ready,
        appVersion: _appVersion,
        help: {'active': _helpActive && sharing, if (_helpActive && sharing) 'password': _password},
        result: result,
      );
      if (identical(result, _pendingResult)) {
        _pendingResult = null;
      }
      if (response != null) {
        next = response.pollAfterSeconds;
        if (mounted) setState(() => _glpiStatus = 'Conectado ao GLPI da Ativa');
        await _handleRequest(response.request);
      }
    } catch (_) {
      // Fora da rede da empresa/VPN: o app segue funcionando sem o GLPI.
      if (mounted) setState(() => _glpiStatus = 'GLPI fora de alcance (sem VPN): passe o código e a senha ao T.I.');
      next = 60;
    }
    _scheduleGlpi(Duration(seconds: (_helpActive || _pendingResult != null) ? 10 : next));
  }

  Future<void> _handleRequest(GlpiRequest? request) async {
    if (request == null || _consentOpen) return;
    final handled = int.tryParse(bind.mainGetLocalOption(key: 'ativa-handled-seq')) ?? 0;
    if (request.seq <= handled) return;
    await bind.mainSetLocalOption(key: 'ativa-handled-seq', value: request.seq.toString());

    if (request.action == 'close') {
      await _endHelp();
      _pendingResult = {'seq': request.seq, 'status': 'closed', 'message': 'Atendimento encerrado no celular.'};
      return;
    }
    // Pedido do T.I. pelo GLPI: o colaborador autoriza aqui.
    _consentOpen = true;
    final who = request.requestedBy.isEmpty ? 'O T.I. da Ativa' : '${request.requestedBy} (T.I.)';
    final accepted = await _explain(
      icon: Icons.support_agent,
      title: 'Pedido de acesso',
      lines: ['$who quer acessar seu celular para ajudar.', 'Você permite?'],
      button: 'PERMITIR',
      cancel: 'NÃO PERMITIR',
    );
    _consentOpen = false;
    if (!accepted) {
      _pendingResult = {'seq': request.seq, 'status': 'rejected', 'message': 'O colaborador não permitiu.'};
      return;
    }
    if (!await _startSharing()) {
      _pendingResult = {'seq': request.seq, 'status': 'failed', 'message': 'O compartilhamento de tela não foi liberado.'};
      return;
    }
    await _refresh();
    setState(() => _helpActive = true);
    _pendingResult = {'seq': request.seq, 'status': 'accepted', 'password': _password, 'message': 'Acesso liberado no celular.'};
  }

  // ------------------------------------------------------------ cadastro (T.I.)

  Future<void> _openSetup() async {
    final code = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _QrScanPage()));
    if (code == null) return;
    final setup = GlpiSetup.parse(code);
    if (setup == null) {
      _toast('Este QR code não é o de cadastro do Ativa Suporte.');
      return;
    }
    final controller = TextEditingController(text: GlpiClient.owner);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quem usa este celular?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Nome do colaborador'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    await GlpiClient.saveSetup(setup, controller.text);
    _toast('Celular cadastrado no GLPI da Ativa.');
    _scheduleGlpi(Duration.zero);
  }

  // ------------------------------------------------------------ tela

  @override
  Widget build(BuildContext context) {
    if (_techConnected) {
      return _sharingScreen();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      body: SafeArea(
        // Cor fixa do texto: com o celular no modo escuro ele vinha branco
        // sobre o fundo claro.
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: kAtivaInk),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
            children: [
              _header(),
              const SizedBox(height: 24),
              if (_helpActive) _helpCard() else if (_ready) _readyCard() else _wizard(),
              const SizedBox(height: 28),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  /// Tela de quando o T.I. esta conectado: bem diferente da tela do codigo,
  /// para ninguem confundir, com o botao de parar.
  Widget _sharingScreen() {
    final names = _server.clients.where((c) => c.authorized && !c.disconnected).map((c) => c.name).where((n) => n.isNotEmpty).toSet();
    return Scaffold(
      backgroundColor: const Color(0xFF1E6B2F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            const Icon(Icons.screen_share, color: Colors.white, size: 96),
            const SizedBox(height: 20),
            const Text('Sua tela está sendo compartilhada',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              names.isEmpty
                  ? 'O T.I. da Ativa está vendo e controlando o seu celular.'
                  : 'O T.I. da Ativa (${names.join(', ')}) está vendo e controlando o seu celular.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text('Pode soltar o celular enquanto o T.I. trabalha.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 16)),
            const Spacer(),
            SizedBox(
              height: 88,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                onPressed: _confirmStop,
                icon: const Icon(Icons.stop_circle, size: 34),
                label: const Text('PARAR COMPARTILHAMENTO', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Ao parar, o T.I. é desconectado na hora.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.white70, fontSize: 14)),
          ]),
        ),
      ),
    );
  }

  Future<void> _confirmStop() async {
    final stop = await _explain(
      icon: Icons.stop_circle,
      title: 'Parar o compartilhamento?',
      lines: const ['O T.I. será desconectado e não verá mais a sua tela.'],
      button: 'PARAR',
      cancel: 'CONTINUAR AJUDA',
    );
    if (stop) await _endHelp();
  }

  Widget _header() {
    return GestureDetector(
      // T.I.: 7 toques no titulo abrem o RustDesk completo.
      onTap: _secretTap,
      child: Row(children: [
        Image.asset('assets/ativa_logo.png', width: 56, height: 56),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ativa Suporte', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kAtivaBlue)),
            Text('Ajuda do T.I. no seu celular', style: TextStyle(fontSize: 15, color: Colors.black54)),
          ]),
        ),
      ]),
    );
  }

  int _taps = 0;
  DateTime _lastTap = DateTime(2000);
  void _secretTap() {
    final now = DateTime.now();
    _taps = now.difference(_lastTap).inSeconds < 2 ? _taps + 1 : 1;
    _lastTap = now;
    if (_taps >= 7) {
      _taps = 0;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => HomePage()));
    }
  }

  Widget _wizard() {
    final steps = <Widget>[
      if (androidVersion >= 33)
        _StepCard(
          number: 1,
          title: 'Permitir avisos',
          text: 'Para o celular avisar quando o T.I. estiver conectado.',
          done: _notificationOk,
          button: 'PERMITIR AVISOS',
          onTap: _askNotification,
        ),
      _StepCard(
        number: androidVersion >= 33 ? 2 : 1,
        title: 'Permitir o controle da tela',
        text: 'Para o T.I. conseguir tocar na tela durante o atendimento.',
        done: _inputOk,
        button: 'PERMITIR CONTROLE',
        onTap: _askAccessibility,
        // Android 13+: app instalado pelo WhatsApp/navegador tem a
        // Acessibilidade travada ("Configuracao restrita") ate liberar
        // nas informacoes do app.
        helpText: androidVersion >= 33 ? 'Apareceu "Configuração restrita"?' : null,
        onHelp: androidVersion >= 33 ? _unlockRestricted : null,
      ),
      _StepCard(
        number: androidVersion >= 33 ? 3 : 2,
        title: 'Manter o app ativo',
        text: 'Para a ajuda não cair quando a tela apagar.',
        done: _batteryOk,
        button: 'PERMITIR',
        onTap: _askBattery,
      ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Vamos preparar seu celular', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Só na primeira vez. Toque nos botões azuis, um por vez.', style: TextStyle(fontSize: 16, color: Colors.black54)),
      const SizedBox(height: 16),
      ...steps.expand((s) => [s, const SizedBox(height: 12)]),
    ]);
  }

  Widget _readyCard() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Icon(Icons.verified, color: kAtivaGreen, size: 64),
      const SizedBox(height: 8),
      const Text('Tudo pronto!', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      const Text('Quando precisar de ajuda, toque no botão abaixo.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.black54)),
      const SizedBox(height: 24),
      SizedBox(
        height: 96,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: kAtivaGreen,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          onPressed: _starting ? null : _requestHelp,
          icon: _starting
              ? const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
              : const Icon(Icons.support_agent, size: 36),
          label: const Text('PEDIR AJUDA AO T.I.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        ),
      ),
      const SizedBox(height: 20),
      _bigValue('CÓDIGO', _formatId(_id)),
      const SizedBox(height: 12),
      _bigValue('SENHA', _password),
      const SizedBox(height: 6),
      const Text('O T.I. só consegue entrar depois que você tocar em PEDIR AJUDA.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.black54)),
    ]);
  }

  /// Compartilhamento ligado, esperando o T.I. (conectado, aparece a
  /// _sharingScreen no lugar desta).
  Widget _helpCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kAtivaBlue, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.hourglass_top, color: kAtivaBlue, size: 32),
          SizedBox(width: 10),
          Expanded(child: Text('Aguardando o T.I.', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        const Text('Leia o código e a senha para o T.I., ou envie pelo WhatsApp.',
            style: TextStyle(fontSize: 16, color: Colors.black54)),
        const SizedBox(height: 18),
        _bigValue('CÓDIGO', _formatId(_id)),
        const SizedBox(height: 12),
        _bigValue('SENHA', _password),
        const SizedBox(height: 18),
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: kAtivaGreen),
            onPressed: _sendWhatsApp,
            icon: const Icon(Icons.send),
            label: const Text('ENVIAR PELO WHATSAPP', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 60,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: _endHelp,
            icon: const Icon(Icons.stop_circle),
            label: const Text('PARAR COMPARTILHAMENTO', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  Widget _bigValue(String label, String value) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value.replaceAll(' ', '')));
        _toast('$label copiado');
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(color: const Color(0xFFE8F0FB), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kAtivaBlue, letterSpacing: 1)),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(value.isEmpty ? '...' : value,
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 2, color: kAtivaInk)),
          ),
        ]),
      ),
    );
  }

  Widget _footer() {
    return Column(children: [
      if (_glpiStatus.isNotEmpty)
        Text(_glpiStatus, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black45)),
      if (GlpiClient.owner.isNotEmpty)
        Text('Celular de ${GlpiClient.owner}', style: const TextStyle(fontSize: 13, color: Colors.black45)),
      TextButton(
        onPressed: _openSetup,
        child: Text(GlpiClient.configured ? 'Cadastro no GLPI (T.I.)' : 'Cadastrar no GLPI (T.I.)',
            style: const TextStyle(fontSize: 13)),
      ),
      Text('Versão $_appVersion', style: const TextStyle(fontSize: 12, color: Colors.black38)),
    ]);
  }

  // ------------------------------------------------------------ util

  /// "138452976" -> "138 452 976"; "1384529760" -> "138 452 9760" (nunca
  /// um digito sozinho no fim, que confunde quem dita o codigo).
  static String _formatId(String id) {
    final digits = id.replaceAll(' ', '');
    final groups = <String>[];
    var i = 0;
    while (i < digits.length) {
      final left = digits.length - i;
      final size = left == 4 ? 4 : 3;
      groups.add(digits.substring(i, i + (size < left ? size : left)));
      i += size;
    }
    return groups.join(' ');
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, style: const TextStyle(fontSize: 16))));
  }

  Future<bool> _explain({
    required IconData icon,
    required String title,
    required List<String> lines,
    required String button,
    String cancel = 'AGORA NÃO',
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: Icon(icon, size: 44, color: kAtivaBlue),
        title: Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: lines
                .map((l) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(l, style: const TextStyle(fontSize: 17))))
                .toList(),
          ),
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kAtivaBlue),
            onPressed: () => Navigator.pop(context, true),
            child: Text(button, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result == true;
  }
}

class _StepCard extends StatelessWidget {
  final int number;
  final String title;
  final String text;
  final bool done;
  final String button;
  final VoidCallback onTap;
  final String? helpText;
  final VoidCallback? onHelp;

  const _StepCard({
    required this.number,
    required this.title,
    required this.text,
    required this.done,
    required this.button,
    required this.onTap,
    this.helpText,
    this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: done ? kAtivaGreen : const Color(0xFFDDE4F0), width: done ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: done ? kAtivaGreen : kAtivaBlue,
            child: done
                ? const Icon(Icons.check, color: Colors.white)
                : Text('$number', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 8),
        Text(done ? 'Pronto!' : text, style: TextStyle(fontSize: 16, color: done ? kAtivaGreen : Colors.black54)),
        if (!done) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kAtivaBlue),
              onPressed: onTap,
              child: Text(button, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
          if (helpText != null && onHelp != null) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: onHelp,
              icon: const Icon(Icons.help_outline),
              label: Text(helpText!, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ],
      ]),
    );
  }
}

/// Leitor do QR de cadastro (gerado no GLPI). Uso do T.I.
class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  final GlobalKey _qrKey = GlobalKey(debugLabel: 'ativa-qr');
  StreamSubscription? _subscription;
  bool _done = false;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR code do GLPI')),
      body: QRView(
        key: _qrKey,
        overlay: QrScannerOverlayShape(borderColor: kAtivaGreen, borderRadius: 10, borderLength: 30, borderWidth: 10, cutOutSize: 260),
        onQRViewCreated: (controller) {
          _subscription = controller.scannedDataStream.listen((data) {
            final code = data.code;
            if (code != null && !_done) {
              _done = true;
              Navigator.of(context).pop(code);
            }
          });
        },
      ),
    );
  }
}
