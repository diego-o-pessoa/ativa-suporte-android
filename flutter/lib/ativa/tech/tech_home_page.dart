// Ativa Remote T.I.: tela inicial do RustDesk da Ativa no Windows (so o T.I.).
//
// - Login com o usuario do GLPI (so quem tem permissao no Ativa Remote).
// - Lista ao vivo dos computadores e celulares do Ativa Remote.
// - "Conectar": pede o acesso, espera a autorizacao do usuario (ou entra
//   direto) e abre a conexao com a senha da sessao, sem copiar nada.
// - Configuracoes do computador: autorizacao do usuario e "Proteger sempre".
// - Reconexao sozinha quando o usuario do Windows sai ou troca de conta fica
//   no modelo da sessao (models/model.dart, shouldAutoRetryOnOffline).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../common/formatter/id_formatter.dart';
import 'tech_api.dart';

/// Tela inicial do desktop = lista do Ativa Remote (false volta a tela do RustDesk).
const kAtivaTechHome = true;

const _kBlue = Color(0xFF15559F);
const _kGreen = Color(0xFF2FB35A);
const _kInk = Color(0xFF142A5B);
const _kMuted = Color(0xFF6D7DA7);
const _kAmber = Color(0xFFE89A0C);
const _kRed = Color(0xFFDD3F4A);

class AtivaTechHomePage extends StatefulWidget {
  const AtivaTechHomePage({Key? key}) : super(key: key);

  @override
  State<AtivaTechHomePage> createState() => _AtivaTechHomePageState();
}

class _AtivaTechHomePageState extends State<AtivaTechHomePage> {
  final _api = TechApi.instance;
  bool _loggedIn = TechApi.instance.loggedIn;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: Theme.of(context).colorScheme.copyWith(primary: _kBlue),
      ),
      child: _loggedIn
          ? _ClientsView(onLogout: () async {
              await _api.logout();
              if (mounted) setState(() => _loggedIn = false);
            }, onSessionLost: () {
              if (mounted) setState(() => _loggedIn = false);
            })
          : _LoginView(onLoggedIn: () => setState(() => _loggedIn = true)),
    );
  }
}

// ---------------------------------------------------------------- login

class _LoginView extends StatefulWidget {
  final VoidCallback onLoggedIn;
  const _LoginView({required this.onLoggedIn});

  @override
  State<_LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<_LoginView> {
  final _url = TextEditingController(text: TechApi.instance.glpiUrl);
  final _login = TextEditingController(text: TechApi.instance.userName);
  final _password = TextEditingController();
  final _totp = TextEditingController();
  bool _busy = false;
  bool _needTotp = false;
  bool _showServer = false;
  String _error = '';

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await TechApi.instance
          .login(_url.text, _login.text, _password.text, totp: _totp.text);
      widget.onLoggedIn();
    } on TechApiError catch (e) {
      setState(() {
        _error = e.message;
        if (e.code == 'TOTP_REQUIRED' || e.code == 'TOTP_INVALID')
          _needTotp = true;
        if (e.code == 'OFFLINE' ||
            e.code == 'BAD_URL' ||
            e.code == 'BAD_RESPONSE') _showServer = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const _Brand(),
            const SizedBox(height: 28),
            const Text('Entre com o seu usuário do GLPI',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: _kInk)),
            const SizedBox(height: 4),
            const Text(
                'Só para o T.I.: é preciso ter permissão no Ativa Remote.',
                style: TextStyle(fontSize: 13, color: _kMuted)),
            const SizedBox(height: 16),
            TextField(
              controller: _login,
              autofocus: _login.text.isEmpty,
              decoration: const InputDecoration(
                  labelText: 'Usuário', prefixIcon: Icon(Icons.person_outline)),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _password,
              autofocus: _login.text.isNotEmpty,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Senha', prefixIcon: Icon(Icons.lock_outline)),
              onSubmitted: (_) => _submit(),
            ),
            if (_needTotp) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _totp,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'Código de verificação (2 etapas)',
                    prefixIcon: Icon(Icons.verified_user_outlined)),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_showServer) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _url,
                decoration: const InputDecoration(
                    labelText: 'Endereço do GLPI',
                    prefixIcon: Icon(Icons.dns_outlined)),
                onSubmitted: (_) => _submit(),
              ),
            ],
            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_error, style: const TextStyle(color: _kRed, fontSize: 13)),
            ],
            const SizedBox(height: 18),
            SizedBox(
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _kBlue),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('ENTRAR',
                        style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            if (!_showServer)
              TextButton(
                onPressed: () => setState(() => _showServer = true),
                child: const Text('Mudar o endereço do GLPI',
                    style: TextStyle(fontSize: 12)),
              ),
          ]),
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset('assets/ativa_logo.png',
              width: 44,
              height: 44,
              errorBuilder: (_, __, ___) => const SizedBox()),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Ativa Remote T.I.',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w800, color: _kBlue)),
            Text('Acesso remoto da Ativa',
                style: TextStyle(fontSize: 12, color: _kMuted)),
          ]),
        ]);
  }
}

// ---------------------------------------------------------------- lista

enum _Filter { all, online, session, protected }

class _ClientsView extends StatefulWidget {
  final Future<void> Function() onLogout;
  final VoidCallback onSessionLost;
  const _ClientsView({required this.onLogout, required this.onSessionLost});

  @override
  State<_ClientsView> createState() => _ClientsViewState();
}

class _ClientsViewState extends State<_ClientsView> {
  final _api = TechApi.instance;
  final _search = TextEditingController();
  Timer? _timer;
  List<TechClient> _clients = [];
  String _error = '';
  bool _loading = true;
  _Filter _filter = _Filter.all;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _start();
  }

  Future<void> _start() async {
    try {
      final me = await _api.me();
      await _api.applyRendezvous(me['rendezvous'] as Map<String, dynamic>?);
    } on TechApiError catch (e) {
      if (e.needsLogin) {
        widget.onSessionLost();
        return;
      }
    }
    await _refresh();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final clients = await _api.clients();
      if (!mounted) return;
      setState(() {
        _clients = clients;
        _error = '';
        _loading = false;
      });
    } on TechApiError catch (e) {
      if (!mounted) return;
      if (e.needsLogin) {
        _timer?.cancel();
        widget.onSessionLost();
        return;
      }
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  List<TechClient> get _visible {
    final query = _search.text.trim().toLowerCase();
    final list = _clients.where((c) {
      switch (_filter) {
        case _Filter.online:
          if (!c.online) return false;
          break;
        case _Filter.session:
          if (!c.inSession) return false;
          break;
        case _Filter.protected:
          if (!c.protected) return false;
          break;
        case _Filter.all:
          break;
      }
      if (query.isEmpty) return true;
      return c.hostname.toLowerCase().contains(query) ||
          c.username.toLowerCase().contains(query) ||
          c.rustdeskId.contains(query.replaceAll(' ', ''));
    }).toList();
    // Em sessao e pedindo ajuda primeiro; depois online; depois por nome.
    int rank(TechClient c) =>
        c.help ? 0 : (c.inSession ? 1 : (c.online ? 2 : 3));
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : a.hostname.compareTo(b.hostname);
    });
    return list;
  }

  int _count(bool Function(TechClient) test) => _clients.where(test).length;

  // ------------------------------------------------------------ acoes

  Future<String?> _askTiPassword(TechClient client, String message) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Senha do T.I.'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${client.hostname} é protegido. $message'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha do T.I.'),
                onSubmitted: (value) => Navigator.pop(context, value),
              ),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Confirmar')),
        ],
      ),
    );
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? _kRed : null,
      duration: const Duration(seconds: 4),
    ));
  }

  /// Chama a API pedindo a senha do T.I. quando o computador e protegido.
  Future<Map<String, dynamic>?> _withTiPassword(TechClient client,
      Future<Map<String, dynamic>> Function(String tiPassword) call) async {
    var tiPassword = '';
    while (true) {
      try {
        return await call(tiPassword);
      } on TechApiError catch (e) {
        if (e.needsTiPassword) {
          final typed = await _askTiPassword(
              client,
              e.code == 'TI_PASSWORD_INVALID'
                  ? e.message
                  : 'Informe a senha do T.I. para continuar.');
          if (typed == null || typed.isEmpty) return null;
          tiPassword = typed;
          continue;
        }
        if (e.needsLogin) {
          widget.onSessionLost();
          return null;
        }
        _toast(e.message, error: true);
        return null;
      }
    }
  }

  Future<void> _connect(TechClient client) async {
    if (_busy.contains(client.id)) return;
    setState(() => _busy.add(client.id));
    try {
      var tiPassword = '';
      final requested = await _withTiPassword(client, (ti) {
        tiPassword = ti;
        return _api.requestAccess(client.id, tiPassword: ti);
      });
      if (requested == null || !mounted) return;
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _WaitDialog(
            client: client,
            tiPassword: tiPassword,
            askTiPassword: _askTiPassword),
      );
      if (result == null || !mounted) return;
      final id = (result['rustdesk_id'] ?? '').toString();
      final password = (result['password'] ?? '').toString();
      if (id.isEmpty || password.isEmpty) return;
      await connect(context, id, password: password);
    } finally {
      if (mounted) setState(() => _busy.remove(client.id));
      _refresh();
    }
  }

  Future<void> _close(TechClient client) async {
    try {
      await _api.close(client.id);
      _toast(
          'Sessão encerrada em ${client.hostname}. O computador troca a senha em seguida.');
    } on TechApiError catch (e) {
      _toast(e.message, error: true);
    }
    _refresh();
  }

  Future<void> _settings(TechClient client) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _SettingsDialog(
        client: client,
        canAdmin: _api.canAdmin,
        save: (requireConsent, protectedManual) => _withTiPassword(
          client,
          (ti) => _api.settings(client.id,
              requireConsent: requireConsent,
              protectedManual: protectedManual,
              tiPassword: ti),
        ),
      ),
    );
    _refresh();
  }

  Future<void> _connectById() async {
    final id = TextEditingController();
    final password = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Conectar por código'),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Para celulares do app Ativa Suporte ou computadores fora da lista: '
                'digite o código e a senha que a pessoa passou.',
                style: TextStyle(fontSize: 13, color: _kMuted)),
            const SizedBox(height: 12),
            TextField(
                controller: id,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Código')),
            const SizedBox(height: 8),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha'),
              onSubmitted: (_) => Navigator.pop(context, true),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Conectar')),
        ],
      ),
    );
    final code = id.text.replaceAll(' ', '');
    if (go == true && code.isNotEmpty && mounted) {
      await connect(context, code,
          password: password.text.isEmpty ? null : password.text);
    }
  }

  // ------------------------------------------------------------ tela

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const _Brand(),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _connectById,
            icon: const Icon(Icons.dialpad, size: 18),
            label: const Text('Conectar por código'),
          ),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            tooltip: 'Conta',
            onSelected: (value) {
              if (value == 'logout') widget.onLogout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  enabled: false,
                  child: Text(
                      _api.userName.isEmpty ? 'Conectado' : _api.userName)),
              const PopupMenuItem(value: 'logout', child: Text('Sair')),
            ],
            child: Row(children: [
              const Icon(Icons.account_circle_outlined, color: _kMuted),
              const SizedBox(width: 6),
              Text(_api.userName, style: const TextStyle(color: _kInk)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar por computador, usuário ou código',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          _chip('Todos', _Filter.all, _clients.length),
          _chip('Online', _Filter.online, _count((c) => c.online)),
          _chip('Em sessão', _Filter.session, _count((c) => c.inSession)),
          _chip('Protegidos', _Filter.protected, _count((c) => c.protected)),
        ]),
        if (_error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error, style: const TextStyle(color: _kRed)),
          ),
        const SizedBox(height: 10),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : visible.isEmpty
                  ? const Center(
                      child: Text('Nenhum computador encontrado.',
                          style: TextStyle(color: _kMuted)))
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (_, i) => _row(visible[i]),
                    ),
        ),
      ]),
    );
  }

  Widget _chip(String label, _Filter filter, int count) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: ChoiceChip(
        label: Text('$label ($count)'),
        selected: _filter == filter,
        onSelected: (_) => setState(() => _filter = filter),
      ),
    );
  }

  Widget _row(TechClient c) {
    final busy = _busy.contains(c.id);
    final statusColor = !c.online
        ? _kMuted
        : c.status == 'accepted'
            ? _kGreen
            : c.status == 'pending'
                ? _kAmber
                : _kBlue;
    final details = <String>[
      if (c.username.isNotEmpty) c.username,
      if (c.rustdeskId.isNotEmpty) 'Código ${formatID(c.rustdeskId)}',
      if (!c.online) 'offline',
      if (c.statusMessage.isNotEmpty && c.status != null) c.statusMessage,
      if (c.online && c.rustdeskId.isEmpty && c.rustdeskMessage.isNotEmpty)
        c.rustdeskMessage,
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: c.help ? _kAmber : const Color(0x22000000),
            width: c.help ? 2 : 1),
      ),
      child: Row(children: [
        Stack(children: [
          Icon(c.mobile ? Icons.smartphone : Icons.desktop_windows_outlined,
              size: 30, color: _kInk),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: c.online ? _kGreen : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(c.hostname,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _kInk)),
                  if (c.help) _badge('Pedindo ajuda', _kAmber),
                  if (c.protected)
                    _badge('Protegido', _kRed, tooltip: c.protectionReason),
                  if (!c.requireConsent) _badge('Entra direto', _kGreen),
                  if (c.status == 'accepted')
                    _badge('Sessão liberada', _kGreen),
                  if (c.status == 'pending') _badge('Aguardando', _kAmber),
                ]),
            const SizedBox(height: 3),
            Text(details.join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: statusColor)),
          ]),
        ),
        const SizedBox(width: 10),
        if (c.inSession)
          TextButton.icon(
            onPressed: busy ? null : () => _close(c),
            icon:
                const Icon(Icons.stop_circle_outlined, size: 18, color: _kRed),
            label: const Text('Encerrar', style: TextStyle(color: _kRed)),
          ),
        IconButton(
          tooltip: 'Configurações deste computador',
          onPressed: () => _settings(c),
          icon: const Icon(Icons.tune),
        ),
        const SizedBox(width: 4),
        SizedBox(
          height: 36,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _kBlue),
            onPressed: busy || !c.online || c.rustdeskId.isEmpty
                ? null
                : () => _connect(c),
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.cast_connected, size: 18),
            label: const Text('Conectar'),
          ),
        ),
      ]),
    );
  }

  Widget _badge(String text, Color color, {String tooltip = ''}) {
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20)),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color)),
    );
    return tooltip.isEmpty ? badge : Tooltip(message: tooltip, child: badge);
  }
}

// ---------------------------------------------------------------- espera

/// Espera o computador liberar o acesso (com ou sem a autorizacao do
/// usuario) e devolve {rustdesk_id, password}.
class _WaitDialog extends StatefulWidget {
  final TechClient client;
  final String tiPassword;
  final Future<String?> Function(TechClient client, String message)
      askTiPassword;
  const _WaitDialog(
      {required this.client,
      required this.tiPassword,
      required this.askTiPassword});

  @override
  State<_WaitDialog> createState() => _WaitDialogState();
}

class _WaitDialogState extends State<_WaitDialog> {
  static const _maxWait = Duration(minutes: 4);
  final _api = TechApi.instance;
  final _started = DateTime.now();
  Timer? _timer;
  late String _tiPassword = widget.tiPassword;
  String _message = 'Pedindo acesso ao computador…';
  String? _final;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (_polling || _final != null) return;
    _polling = true;
    try {
      final state =
          await _api.connection(widget.client.id, tiPassword: _tiPassword);
      if (!mounted) return;
      final status = state['status']?.toString();
      final message = (state['status_message'] ?? '').toString();
      if (status == 'accepted' &&
          (state['password'] ?? '').toString().isNotEmpty) {
        _timer?.cancel();
        Navigator.pop(context, state);
        return;
      }
      if (status == 'rejected' ||
          status == 'failed' ||
          status == null ||
          status == 'closing') {
        _stop(message.isNotEmpty
            ? message
            : 'O computador não liberou o acesso.');
        return;
      }
      if (DateTime.now().difference(_started) > _maxWait) {
        _stop('O computador não respondeu a tempo. Tente de novo.');
        return;
      }
      setState(() =>
          _message = message.isNotEmpty ? message : 'Aguardando o computador…');
    } on TechApiError catch (e) {
      if (!mounted) return;
      if (e.needsTiPassword) {
        _timer?.cancel();
        final typed = await widget.askTiPassword(widget.client, e.message);
        if (!mounted) return;
        if (typed == null || typed.isEmpty) {
          Navigator.pop(context);
          return;
        }
        _tiPassword = typed;
        _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
      } else if (e.code != 'OFFLINE') {
        _stop(e.message);
      } else {
        setState(() => _message = e.message);
      }
    } finally {
      _polling = false;
    }
  }

  void _stop(String message) {
    _timer?.cancel();
    setState(() => _final = message);
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_final == null) {
      try {
        await _api.close(widget.client.id);
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final waitingUser = _message.toLowerCase().contains('autoriza');
    return AlertDialog(
      title: Text('Conectando a ${widget.client.hostname}'),
      content: SizedBox(
        width: 360,
        child: Row(children: [
          if (_final == null)
            const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3))
          else
            const Icon(Icons.block, color: _kRed, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_final ?? _message,
                      style: const TextStyle(fontSize: 14)),
                  if (_final == null && waitingUser)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                          'O usuário tem 60 segundos para tocar em "Sim".',
                          style: TextStyle(fontSize: 12, color: _kMuted)),
                    ),
                ]),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _cancel,
            child: Text(_final == null ? 'Cancelar' : 'Fechar')),
      ],
    );
  }
}

// ---------------------------------------------------------------- configuracoes

class _SettingsDialog extends StatefulWidget {
  final TechClient client;
  final bool canAdmin;
  final Future<Map<String, dynamic>?> Function(
      bool? requireConsent, bool? protectedManual) save;
  const _SettingsDialog(
      {required this.client, required this.canAdmin, required this.save});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late bool _requireConsent = widget.client.requireConsent;
  late bool _protectedManual = widget.client.protectedManual;
  late bool _protected = widget.client.protected;
  bool _busy = false;

  Future<void> _apply({bool? requireConsent, bool? protectedManual}) async {
    setState(() => _busy = true);
    final state = await widget.save(requireConsent, protectedManual);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (state != null) {
        _requireConsent = state['require_consent'] == true;
        _protectedManual = state['protected_manual'] == true;
        _protected = state['protected'] == true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.client;
    return AlertDialog(
      title: Text(c.hostname),
      content: SizedBox(
        width: 420,
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Pedir autorização do usuário'),
                subtitle: Text(_protected
                    ? 'Computador protegido: a autorização é sempre pedida.'
                    : _requireConsent
                        ? 'O usuário toca em "Sim" antes de cada acesso.'
                        : 'Desligado: o T.I. entra direto, sem perguntar.'),
                value: _requireConsent,
                onChanged: _busy || _protected
                    ? null
                    : (value) => _apply(requireConsent: value),
              ),
              if (widget.canAdmin) ...[
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Proteger sempre'),
                  subtitle: const Text(
                      'Pede a senha do T.I. para conectar e sempre a autorização do usuário. '
                      'Só administradores do GLPI mudam.'),
                  value: _protectedManual,
                  onChanged:
                      _busy ? null : (value) => _apply(protectedManual: value),
                ),
              ],
              if (_protected && c.protectionReason.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Protegido: ${c.protectionReason}',
                      style: const TextStyle(fontSize: 12, color: _kMuted)),
                ),
              if (c.rustdeskVersion.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('RustDesk ${c.rustdeskVersion}',
                      style: const TextStyle(fontSize: 12, color: _kMuted)),
                ),
            ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'))
      ],
    );
  }
}
