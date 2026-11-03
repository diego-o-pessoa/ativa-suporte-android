// Ativa Suporte: tela unica do app para o colaborador.
//
// 1. Primeira vez: assistente com as permissoes, um botao grande por passo
//    (avanca sozinho quando o Android confirma).
// 2. Pronto: botao "PEDIR AJUDA AO T.I.". Ele liga o compartilhamento de
//    tela (o Android pede "Comecar agora" toda vez - regra do sistema) e
//    mostra o codigo e a senha em letras grandes, com envio pelo WhatsApp.
// 3. Com o GLPI ao alcance (rede da empresa/VPN), o celular tambem aparece
//    no Ativa Remote e o T.I. pode pedir o acesso por la.

import 'dart:async';

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou das configuracoes do Android: confere as permissoes na hora.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  void _onServerChanged() {
    // O compartilhamento parou por fora (notificacao, sistema): encerra a ajuda.
    if (_helpActive && !_starting && !_server.isStart) {
      setState(() => _helpActive = false);
    } else if (mounted) {
      setState(() {});
    }
  }

  /// Senha temporaria de 8 caracteres e entrada so com senha (sem a janela
  /// extra de "Aceitar" do RustDesk: a autorizacao e o proprio "Pedir ajuda").
  Future<void> _configureRustDesk() async {
    await bind.mainSetOption(key: kOptionApproveMode, value: 'password');
    await bind.mainSetOption(key: kOptionVerificationMethod, value: kUseTemporaryPassword);
    await bind.mainSetOption(key: 'temporary-password-length', value: '8');
    await bind.mainSetLocalOption(key: kOptionDisableFloatingWindow, value: 'Y');
  }

  Future<void> _refresh() async {
    if (!mounted) return;
    gFFI.invokeMethod('check_service');
    final notification = androidVersion < 33 || await AndroidPermissionManager.check(kAndroid13Notification);
    final battery = await AndroidPermissionManager.check(kRequestIgnoreBatteryOptimizations);
    final id = await bind.mainGetMyId();
    final password = await bind.mainGetTemporaryPassword();
    if (!mounted) return;
    setState(() {
      _notificationOk = notification;
      _batteryOk = battery;
      _id = id;
      _password = password;
    });
  }

  bool get _inputOk => _server.inputOk;
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
    final go = await _explain(
      icon: Icons.touch_app,
      title: 'Permitir o controle da tela',
      lines: const [
        'Na próxima tela:',
        '1. Toque em "Aplicativos instalados" (ou "Serviços baixados").',
        '2. Toque em "Ativa Suporte".',
        '3. Ligue a chave e toque em "Permitir".',
        '4. Volte para este aplicativo.',
      ],
      button: 'ABRIR CONFIGURAÇÕES',
    );
    if (go) {
      AndroidPermissionManager.startAction(kActionAccessibilitySettings);
    }
  }

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
      await _server.stopService();
    }
    // Senha nova a cada atendimento: a anterior deixa de valer.
    await bind.mainUpdateTemporaryPassword();
    _refresh();
  }

  Future<void> _requestHelp() async {
    if (!await _startSharing()) return;
    setState(() => _helpActive = true);
    await _refresh();
    _scheduleGlpi(Duration.zero);
  }

  Future<void> _endHelp() async {
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
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      body: SafeArea(
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
    );
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
    ]);
  }

  Widget _helpCard() {
    final connected = _server.clients.any((c) => !c.disconnected);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: connected ? kAtivaGreen : kAtivaBlue, width: 2),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(connected ? Icons.headset_mic : Icons.hourglass_top, color: connected ? kAtivaGreen : kAtivaBlue, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(connected ? 'O T.I. está no seu celular' : 'Aguardando o T.I.',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          connected
              ? 'Pode soltar o celular. Para encerrar, toque no botão vermelho.'
              : 'Leia o código e a senha para o T.I., ou envie pelo WhatsApp.',
          style: const TextStyle(fontSize: 16, color: Colors.black54),
        ),
        const SizedBox(height: 18),
        _bigValue('CÓDIGO', _formatId(_id)),
        const SizedBox(height: 12),
        _bigValue('SENHA', _password),
        const SizedBox(height: 18),
        if (!connected)
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
            label: const Text('ENCERRAR AJUDA', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 2)),
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

  static String _formatId(String id) {
    final digits = id.replaceAll(' ', '');
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && i % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    return buffer.toString();
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
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: lines
              .map((l) => Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(l, style: const TextStyle(fontSize: 17))))
              .toList(),
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

  const _StepCard({
    required this.number,
    required this.title,
    required this.text,
    required this.done,
    required this.button,
    required this.onTap,
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
