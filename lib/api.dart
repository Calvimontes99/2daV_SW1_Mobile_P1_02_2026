import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Servidor por defecto: el backend local por `adb reverse tcp:8083 tcp:8083`, o el que se pase con
/// `--dart-define=API_URL=https://...`. En la pantalla de inicio se puede cambiar.
const String servidorPorDefecto = String.fromEnvironment('API_URL', defaultValue: 'http://127.0.0.1:8083');

class ErrorApi implements Exception {
  ErrorApi(this.mensaje, [this.estado]);
  final String mensaje;
  final int? estado;
  @override
  String toString() => mensaje;
}

/// Sesión guardada en el teléfono (servidor, token y nombre del usuario).
class Sesion {
  Sesion({required this.servidor, required this.token, required this.nombre, required this.id, required this.email});
  final String servidor;
  final String token;
  final String nombre;
  final int id;
  final String email;

  static Future<Sesion?> leer() async {
    final p = await SharedPreferences.getInstance();
    final token = p.getString('token');
    if (token == null || token.isEmpty) return null;
    return Sesion(
      servidor: p.getString('servidor') ?? servidorPorDefecto,
      token: token,
      nombre: p.getString('nombre') ?? '',
      id: p.getInt('id') ?? 0,
      email: p.getString('email') ?? '',
    );
  }

  Future<void> guardar() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('servidor', servidor);
    await p.setString('token', token);
    await p.setString('nombre', nombre);
    await p.setInt('id', id);
    await p.setString('email', email);
  }

  static Future<void> cerrar() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('token');
  }

  static Future<String> ultimoServidor() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('servidor') ?? servidorPorDefecto;
  }
}

/// Cliente de la API del diagramador (la misma que usa la web).
class Api {
  Api(this.sesion);
  final Sesion sesion;

  Uri _uri(String ruta) => Uri.parse('${sesion.servidor}$ruta');
  Map<String, String> get _cabeceras => {'Content-Type': 'application/json', 'Authorization': 'Bearer ${sesion.token}'};

  static dynamic _datos(http.Response r) {
    dynamic cuerpo;
    try {
      cuerpo = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      cuerpo = null;
    }
    if (r.statusCode >= 400) {
      final mensaje = cuerpo is Map && cuerpo['message'] is String
          ? cuerpo['message'] as String
          : (r.statusCode == 401 || r.statusCode == 403)
              ? 'Tu sesión expiró. Inicia sesión de nuevo.'
              : 'El servidor respondió ${r.statusCode}.';
      throw ErrorApi(mensaje, r.statusCode);
    }
    return cuerpo is Map && cuerpo.containsKey('data') ? cuerpo['data'] : cuerpo;
  }

  static Future<Sesion> iniciarSesion(String servidor, String email, String clave) async {
    final base = servidor.trim().replaceAll(RegExp(r'/+$'), '');
    final http.Response r;
    try {
      r = await http
          .post(Uri.parse('$base/apis/login'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'email': email.trim(), 'password': clave}))
          .timeout(const Duration(seconds: 25));
    } catch (_) {
      throw ErrorApi('No se pudo conectar con $base. Revisa la dirección y que el servidor esté encendido.');
    }
    final datos = _datos(r) as Map;
    final usuario = (datos['user'] as Map?) ?? {};
    final sesion = Sesion(
      servidor: base,
      token: datos['token'] as String,
      nombre: (usuario['name'] ?? usuario['email'] ?? email) as String,
      id: (usuario['id'] as num?)?.toInt() ?? 0,
      email: (usuario['email'] ?? email) as String,
    );
    await sesion.guardar();
    return sesion;
  }

  Future<List<Map<String, dynamic>>> salas() async {
    final r = await http.get(_uri('/apis/colaboracion/salas'), headers: _cabeceras).timeout(const Duration(seconds: 25));
    return List<Map<String, dynamic>>.from(_datos(r) as List);
  }

  Future<List<Map<String, dynamic>>> mensajes(int salaId) async {
    final r = await http.get(_uri('/apis/colaboracion/$salaId/mensajes?limite=100'), headers: _cabeceras);
    return List<Map<String, dynamic>>.from((_datos(r) as Map)['mensajes'] as List);
  }

  Future<List<Map<String, dynamic>>> propuestas(int salaId) async {
    final r = await http.get(_uri('/apis/colaboracion/$salaId/propuestas'), headers: _cabeceras);
    return List<Map<String, dynamic>>.from(_datos(r) as List);
  }

  Future<List<Map<String, dynamic>>> cambios(int salaId) async {
    final r = await http.get(_uri('/apis/colaboracion/$salaId/cambios?limite=200'), headers: _cabeceras);
    return List<Map<String, dynamic>>.from(_datos(r) as List);
  }

  Future<Map<String, dynamic>?> novedades(int salaId) async {
    final r = await http.get(_uri('/apis/colaboracion/$salaId/novedades'), headers: _cabeceras);
    final d = _datos(r);
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  Future<void> enviar(int salaId, String texto, {bool paraIA = false}) async {
    final r = await http.post(_uri('/apis/colaboracion/$salaId/mensajes'), headers: _cabeceras, body: jsonEncode({'texto': texto, 'paraIA': paraIA}));
    _datos(r);
  }

  Future<void> registrarDispositivo(String token) async {
    final r = await http.post(_uri('/apis/colaboracion/dispositivos'), headers: _cabeceras, body: jsonEncode({'token': token, 'plataforma': 'android'}));
    _datos(r);
  }

  Future<void> quitarDispositivo(String token) async {
    final r = await http.delete(_uri('/apis/colaboracion/dispositivos'), headers: _cabeceras, body: jsonEncode({'token': token}));
    _datos(r);
  }

  Future<void> decidir(int salaId, int propuestaId, String decision) async {
    final r = await http.post(_uri('/apis/colaboracion/$salaId/propuestas/$propuestaId'), headers: _cabeceras, body: jsonEncode({'decision': decision}));
    _datos(r);
  }
}
