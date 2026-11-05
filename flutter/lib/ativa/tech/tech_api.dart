// Ativa Remote T.I.: cliente da API do plugin Ativa Remote no GLPI
// (/plugins/ativaremote/api/v1/tech). Login com o usuario do GLPI; o token
// fica nas opcoes locais do app (vale 7 dias sem uso, revogado no "Sair").

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../models/platform_model.dart';

const kAtivaDefaultGlpiUrl = 'https://chamados.ativalocacao.com.br:8443';

const _kUrlKey = 'ativa-tech-glpi-url';
const _kTokenKey = 'ativa-tech-token';
const _kUserKey = 'ativa-tech-user';
const _kAdminKey = 'ativa-tech-admin';

class TechApiError implements Exception {
  final String code;
  final String message;
  final int status;
  TechApiError(this.code, this.message, this.status);

  bool get needsLogin => status == 401 && (code == 'UNAUTHORIZED');
  bool get needsTiPassword =>
      code == 'TI_PASSWORD_REQUIRED' || code == 'TI_PASSWORD_INVALID';

  @override
  String toString() => message;
}

/// Computador (ou celular) da lista do Ativa Remote.
class TechClient {
  final Map<String, dynamic> raw;
  TechClient(this.raw);

  int get id => (raw['id'] as num?)?.toInt() ?? 0;
  String get hostname => (raw['hostname'] ?? '').toString();
  String get username => (raw['username'] ?? '').toString();
  bool get online => raw['online'] == true;
  bool get mobile => raw['device'] == 'mobile';
  bool get protected => raw['protected'] == true;
  bool get protectedManual => raw['protected_manual'] == true;
  String get protectionReason => (raw['protection_reason'] ?? '').toString();
  bool get requireConsent => raw['require_consent'] == true;
  bool get help => raw['help'] == true;
  String? get status => raw['status']?.toString();
  String get statusMessage => (raw['status_message'] ?? '').toString();
  String get rustdeskId => (raw['rustdesk_id'] ?? '').toString();
  String get rustdeskVersion => (raw['rustdesk_version'] ?? '').toString();
  String get rustdeskMessage => (raw['rustdesk_message'] ?? '').toString();
  int get lastCheck => (raw['last_check_ts'] as num?)?.toInt() ?? 0;
  bool get inSession => status == 'pending' || status == 'accepted';
}

class TechApi {
  TechApi._();
  static final TechApi instance = TechApi._();

  final _client = http.Client();

  String get glpiUrl {
    final saved = bind.mainGetLocalOption(key: _kUrlKey).trim();
    return saved.isEmpty ? kAtivaDefaultGlpiUrl : saved;
  }

  String get token => bind.mainGetLocalOption(key: _kTokenKey);
  String get userName => bind.mainGetLocalOption(key: _kUserKey);
  bool get canAdmin => bind.mainGetLocalOption(key: _kAdminKey) == 'Y';
  bool get loggedIn => token.isNotEmpty;

  Uri _uri(String path, [String? base]) {
    var root = (base ?? glpiUrl).trim();
    while (root.endsWith('/')) {
      root = root.substring(0, root.length - 1);
    }
    return Uri.parse('$root/plugins/ativaremote/api/v1/tech$path');
  }

  Future<Map<String, dynamic>> _send(String method, String path,
      {Map<String, dynamic>? body, String? base, bool auth = true}) async {
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'User-Agent': 'AtivaRemoteTI',
    };
    if (auth) {
      headers['Authorization'] = 'Bearer $token';
    }
    http.Response response;
    try {
      final uri = _uri(path, base);
      response = method == 'GET'
          ? await _client
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 20))
          : await _client
              .post(uri, headers: headers, body: jsonEncode(body ?? const {}))
              .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw TechApiError('OFFLINE',
          'O GLPI não respondeu. Confira a VPN ou a rede da empresa.', 0);
    } on SocketException {
      throw TechApiError('OFFLINE',
          'Sem conexão com o GLPI. Confira a VPN ou a rede da empresa.', 0);
    } on HandshakeException {
      throw TechApiError('OFFLINE', 'Falha no certificado HTTPS do GLPI.', 0);
    } on FormatException {
      throw TechApiError('BAD_URL', 'Endereço do GLPI inválido.', 0);
    } on http.ClientException catch (e) {
      throw TechApiError(
          'OFFLINE', 'Sem conexão com o GLPI (${e.message}).', 0);
    }
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      throw TechApiError(
          'BAD_RESPONSE',
          response.statusCode == 404
              ? 'O GLPI não tem a API do app (atualize o plugin Ativa Remote).'
              : 'Resposta inválida do GLPI (HTTP ${response.statusCode}).',
          response.statusCode);
    }
    if (response.statusCode >= 400 || data['error'] is Map) {
      final error = (data['error'] as Map?) ?? const {};
      final apiError = TechApiError(
          (error['code'] ?? 'ERROR').toString(),
          (error['message'] ?? 'Erro HTTP ${response.statusCode}.').toString(),
          response.statusCode);
      if (apiError.needsLogin && auth) {
        await _forget();
      }
      throw apiError;
    }
    return data;
  }

  Future<void> _forget() async {
    await bind.mainSetLocalOption(key: _kTokenKey, value: '');
  }

  /// Login com o usuario do GLPI. [totp] so quando o GLPI pedir.
  Future<void> login(String url, String login, String password,
      {String totp = ''}) async {
    final data = await _send('POST', '/login', base: url, auth: false, body: {
      'login': login,
      'password': password,
      'totp': totp,
      'device': Platform.localHostname
    });
    await bind.mainSetLocalOption(key: _kUrlKey, value: url.trim());
    await bind.mainSetLocalOption(
        key: _kTokenKey, value: (data['token'] ?? '').toString());
    await bind.mainSetLocalOption(
        key: _kUserKey,
        value: ((data['user'] as Map?)?['name'] ?? '').toString());
    await bind.mainSetLocalOption(
        key: _kAdminKey, value: data['can_admin'] == true ? 'Y' : 'N');
  }

  Future<void> logout() async {
    try {
      await _send('POST', '/logout');
    } catch (_) {
      // Sem rede: o token vence sozinho em 7 dias.
    }
    await _forget();
  }

  Future<Map<String, dynamic>> me() async {
    final data = await _send('GET', '/me');
    await bind.mainSetLocalOption(
        key: _kAdminKey, value: data['can_admin'] == true ? 'Y' : 'N');
    return data;
  }

  Future<List<TechClient>> clients() async {
    final data = await _send('GET', '/clients');
    final list = (data['clients'] as List?) ?? const [];
    return list.whereType<Map<String, dynamic>>().map(TechClient.new).toList();
  }

  Future<Map<String, dynamic>> requestAccess(int id,
          {String tiPassword = ''}) =>
      _send('POST', '/clients/$id/request',
          body: {if (tiPassword.isNotEmpty) 'ti_password': tiPassword});

  /// Situacao do pedido; liberado, traz rustdesk_id e password.
  Future<Map<String, dynamic>> connection(int id,
          {String tiPassword = '', bool reconnect = false}) =>
      _send('POST', '/clients/$id/connection', body: {
        if (tiPassword.isNotEmpty) 'ti_password': tiPassword,
        if (reconnect) 'reconnect': true,
      });

  Future<Map<String, dynamic>> close(int id) =>
      _send('POST', '/clients/$id/close');

  Future<Map<String, dynamic>> settings(int id,
          {bool? requireConsent,
          bool? protectedManual,
          String tiPassword = ''}) =>
      _send('POST', '/clients/$id/settings', body: {
        if (requireConsent != null) 'require_consent': requireConsent,
        if (protectedManual != null) 'protected_manual': protectedManual,
        if (tiPassword.isNotEmpty) 'ti_password': tiPassword,
      });

  /// Usa o servidor RustDesk proprio da Ativa quando o GLPI informa um
  /// (vazio = servidor publico, como antes).
  Future<void> applyRendezvous(Map<String, dynamic>? rendezvous) async {
    final host = (rendezvous?['host'] ?? '').toString();
    final key = (rendezvous?['key'] ?? '').toString();
    final wanted = {
      'custom-rendezvous-server': host,
      'key': key,
      'relay-server': '',
      'api-server': '',
    };
    for (final entry in wanted.entries) {
      final current = await bind.mainGetOption(key: entry.key);
      if (current != entry.value) {
        await bind.mainSetOption(key: entry.key, value: entry.value);
      }
    }
  }
}
