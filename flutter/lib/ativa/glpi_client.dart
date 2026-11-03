// Ativa Suporte: conversa com o Ativa Remote do GLPI.
//
// O celular se cadastra por um QR code gerado no GLPI (Ativa Remote >
// Configuracoes > Celulares). O QR traz o endereco da API e o token dos
// celulares - nada disso fica no codigo do app. O GLPI so e alcancado pela
// rede da empresa ou pela VPN: sem ele, o app continua funcionando (o
// colaborador le o codigo e a senha para o T.I.).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;

import '../models/platform_model.dart';

class AtivaKeys {
  static const apiUrl = 'ativa-glpi-api';
  static const token = 'ativa-glpi-token';
  static const deviceGuid = 'ativa-device-guid';
  static const owner = 'ativa-owner';
}

/// Pedido do T.I. vindo do GLPI ("open" = acessar, "close" = encerrar).
class GlpiRequest {
  final int seq;
  final String action;
  final String requestedBy;
  GlpiRequest(this.seq, this.action, this.requestedBy);
}

class GlpiResponse {
  final GlpiRequest? request;
  final int pollAfterSeconds;
  GlpiResponse(this.request, this.pollAfterSeconds);
}

/// Conteudo do QR de cadastro:
/// ativasuporte://setup?api=<url da API>&token=<token dos celulares>
class GlpiSetup {
  final String apiUrl;
  final String token;
  GlpiSetup(this.apiUrl, this.token);

  static GlpiSetup? parse(String text) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null || uri.scheme != 'ativasuporte' || uri.host != 'setup') {
      return null;
    }
    final api = uri.queryParameters['api'] ?? '';
    final token = uri.queryParameters['token'] ?? '';
    final apiUri = Uri.tryParse(api);
    if (apiUri == null || apiUri.scheme != 'https' || token.length < 32) {
      return null;
    }
    return GlpiSetup(api.replaceAll(RegExp(r'/+$'), ''), token);
  }
}

class GlpiClient {
  static bool get configured =>
      bind.mainGetLocalOption(key: AtivaKeys.apiUrl).isNotEmpty &&
      bind.mainGetLocalOption(key: AtivaKeys.token).isNotEmpty;

  static Future<void> saveSetup(GlpiSetup setup, String owner) async {
    await bind.mainSetLocalOption(key: AtivaKeys.apiUrl, value: setup.apiUrl);
    await bind.mainSetLocalOption(key: AtivaKeys.token, value: setup.token);
    await bind.mainSetLocalOption(key: AtivaKeys.owner, value: owner.trim());
  }

  static String get owner => bind.mainGetLocalOption(key: AtivaKeys.owner);

  /// Identificador fixo deste celular no GLPI (gerado uma vez).
  static Future<String> deviceGuid() async {
    var guid = bind.mainGetLocalOption(key: AtivaKeys.deviceGuid);
    if (RegExp(r'^[a-f0-9]{32}$').hasMatch(guid)) {
      return guid;
    }
    final random = Random.secure();
    guid = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await bind.mainSetLocalOption(key: AtivaKeys.deviceGuid, value: guid);
    return guid;
  }

  /// Nome do celular no painel: "CEL-SM-A145M-3F2A" (so letras, numeros e -).
  static Future<String> deviceName(String guid) async {
    var model = 'ANDROID';
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      model = info.model;
    } catch (_) {}
    final clean = model.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '-').replaceAll(RegExp(r'^-+|-+$'), '');
    final short = clean.length > 24 ? clean.substring(0, 24) : clean;
    return 'CEL-${short.isEmpty ? 'ANDROID' : short}-${guid.substring(0, 4).toUpperCase()}';
  }

  /// Relatorio ao GLPI. [help]: ajuda pedida pelo colaborador (com a senha
  /// da sessao). [result]: resposta a um pedido do T.I.
  static Future<GlpiResponse?> report({
    required String rustdeskId,
    required bool ready,
    required String appVersion,
    Map<String, dynamic>? help,
    Map<String, dynamic>? result,
  }) async {
    if (!configured) {
      return null;
    }
    final api = bind.mainGetLocalOption(key: AtivaKeys.apiUrl);
    final token = bind.mainGetLocalOption(key: AtivaKeys.token);
    final guid = await deviceGuid();
    final payload = <String, dynamic>{
      'machine_guid': guid,
      'hostname': await deviceName(guid),
      'client_version': appVersion,
      'owner': owner,
      'rustdesk': {
        'installed': true,
        'ready': ready,
        'id': rustdeskId,
        'version': 'ativa-$appVersion',
        'message': ready ? '' : 'Permissoes pendentes no celular.',
      },
      if (help != null) 'help': help,
      if (result != null) 'result': result,
    };
    final response = await http
        .post(Uri.parse('$api/report'),
            headers: {
              HttpHeaders.authorizationHeader: 'Bearer $token',
              HttpHeaders.contentTypeHeader: 'application/json',
              HttpHeaders.acceptHeader: 'application/json',
            },
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw HttpException('GLPI respondeu HTTP ${response.statusCode}');
    }
    final data = jsonDecode(response.body);
    if (data is! Map) {
      throw const FormatException('Resposta invalida do GLPI');
    }
    GlpiRequest? request;
    final raw = data['request'];
    if (raw is Map && raw['seq'] is int && (raw['action'] == 'open' || raw['action'] == 'close')) {
      request = GlpiRequest(raw['seq'] as int, raw['action'] as String, (raw['requested_by'] ?? '').toString());
    }
    final poll = data['poll_after_seconds'];
    return GlpiResponse(request, poll is int ? poll.clamp(5, 300) : 30);
  }
}
