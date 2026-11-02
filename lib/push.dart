import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Notificaciones push con Firebase Cloud Messaging: llegan aunque la app esté cerrada.
///
/// Se activa sola cuando el proyecto tiene android/app/google-services.json (proyecto de Firebase
/// gratuito). Sin ese archivo, Firebase no se inicia y la app sigue avisando con notificaciones
/// locales mientras está abierta o en segundo plano.
class Push {
  Push._();
  static final Push instancia = Push._();

  bool disponible = false;
  StreamSubscription<String>? _renovacion;
  // Cambia en cada inicio y cierre de sesión: lo que termina tarde para una sesión que ya se cerró
  // se descarta o se deshace
  int _generacion = 0;
  // Tokens que el servidor tiene registrados para la sesión actual
  final Set<String> _registrados = {};
  // Bajas que todavía no se confirmaron (token → sesión con la que se registró). Una baja fallida
  // NO se olvida: se reintenta en el próximo cierre o inicio de sesión y al abrir la app.
  final Map<String, Sesion> _bajasPendientes = {};
  // Registrar y quitar van en fila y en orden: un registro que ya estaba en curso termina antes
  // de que el cierre de sesión quite los tokens (antes podía terminar después y reinscribir el teléfono)
  Future<void> _cola = Future.value();

  Future<void> _enCola(Future<void> Function() tarea) {
    final siguiente = _cola.then((_) => tarea()).catchError((Object e) => debugPrint('Push: $e'));
    _cola = siguiente;
    return siguiente;
  }

  /// Qué hacer al tocar una notificación (abrir la sala).
  void Function(int salaId, String titulo)? alTocar;

  Future<void> iniciar() async {
    try {
      await Firebase.initializeApp();
      disponible = true;
      // Bajas que quedaron pendientes de una sesión anterior (la app se cerró sin poder hacerlas)
      await _cargarBajas();
      _enCola(_procesarBajas);
    } catch (e) {
      debugPrint('Push: Firebase no está configurado (falta google-services.json): $e');
      return;
    }
    // Tocar la notificación con la app en segundo plano o cerrada
    FirebaseMessaging.onMessageOpenedApp.listen(_abrir);
    final inicial = await FirebaseMessaging.instance.getInitialMessage();
    if (inicial != null) {
      // Se espera a que la app tenga su navegador listo
      Future.delayed(const Duration(milliseconds: 600), () => _abrir(inicial));
    }
  }

  void _abrir(RemoteMessage mensaje) {
    final salaId = int.tryParse('${mensaje.data['salaId'] ?? ''}');
    if (salaId != null) alTocar?.call(salaId, '${mensaje.data['titulo'] ?? 'Sala'}');
  }

  /// Registra este teléfono en el servidor para recibir avisos de las salas del usuario.
  Future<void> registrar(Sesion sesion) async {
    if (!disponible) return;
    final generacion = ++_generacion;
    bool vigente() => generacion == _generacion;
    // Primero se terminan las bajas de cuentas anteriores que habían fallado
    _enCola(_procesarBajas);
    await _enCola(() async {
      if (!vigente()) return;
      await FirebaseMessaging.instance.requestPermission();
      final token = await FirebaseMessaging.instance.getToken();
      if (!vigente() || token == null) return;
      await _inscribir(sesion, token, vigente);
    });
    if (!vigente()) return;
    await _renovacion?.cancel();
    _renovacion = FirebaseMessaging.instance.onTokenRefresh.listen((nuevo) {
      _enCola(() async {
        if (vigente()) await _inscribir(sesion, nuevo, vigente);
      });
    });
  }

  /// Registra un token y, si mientras tanto se cerró la sesión, lo vuelve a quitar enseguida.
  Future<void> _inscribir(Sesion sesion, String token, bool Function() vigente) async {
    await Api(sesion).registrarDispositivo(token);
    _registrados.add(token);
    if (!vigente()) {
      try {
        await Api(sesion).quitarDispositivo(token);
      } catch (_) {}
      _registrados.remove(token);
    }
  }

  /// Al cerrar sesión, el teléfono deja de recibir avisos de esa cuenta. No espera a los registros
  /// en curso (la pantalla sigue al instante): la baja queda en fila detrás de ellos.
  Future<void> olvidar(Sesion sesion) async {
    _generacion++; // invalida registros en curso y renovaciones de la sesión anterior
    final renovacion = _renovacion;
    _renovacion = null;
    await renovacion?.cancel();
    if (!disponible) return;
    _enCola(() async {
      for (final token in _registrados.toList()) {
        _bajasPendientes[token] = sesion;
      }
      _registrados.clear();
      await _procesarBajas();
    });
  }

  /// Intenta todas las bajas pendientes; las que fallan quedan para el próximo intento.
  Future<void> _procesarBajas() async {
    for (final entrada in _bajasPendientes.entries.toList()) {
      try {
        await Api(entrada.value).quitarDispositivo(entrada.key);
        _bajasPendientes.remove(entrada.key);
      } catch (e) {
        debugPrint('Push: la baja del dispositivo falló, se reintentará: $e');
      }
    }
    // El guardado en el teléfono no frena la fila: la lista en memoria ya manda
    unawaited(_guardarBajas());
  }

  static const _claveBajas = 'push.bajasPendientes';

  /// Las bajas pendientes se guardan en el teléfono para reintentarlas aunque se cierre la app.
  Future<void> _guardarBajas() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_claveBajas, jsonEncode([
        for (final e in _bajasPendientes.entries)
          {'token': e.key, 'servidor': e.value.servidor, 'sesion': e.value.token, 'id': e.value.id, 'nombre': e.value.nombre, 'email': e.value.email},
      ]));
    } catch (e) {
      debugPrint('Push: no se pudieron guardar las bajas pendientes: $e');
    }
  }

  Future<void> _cargarBajas() async {
    try {
      final p = await SharedPreferences.getInstance();
      final lista = jsonDecode(p.getString(_claveBajas) ?? '[]') as List;
      for (final x in lista) {
        if (x is! Map) continue;
        _bajasPendientes['${x['token']}'] = Sesion(
          servidor: '${x['servidor']}', token: '${x['sesion']}', nombre: '${x['nombre'] ?? ''}',
          id: (x['id'] as num?)?.toInt() ?? 0, email: '${x['email'] ?? ''}',
        );
      }
    } catch (e) {
      debugPrint('Push: no se pudieron leer las bajas pendientes: $e');
    }
  }
}
