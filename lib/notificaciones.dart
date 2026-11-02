import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notificaciones del teléfono: avisan de mensajes, propuestas de la IA y cambios del diagrama
/// cuando la app no está en primer plano (por ejemplo, con el teléfono en el bolsillo).
class Notificaciones with WidgetsBindingObserver {
  Notificaciones._();
  static final Notificaciones instancia = Notificaciones._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _listo = false;
  bool enPrimerPlano = true;
  int _siguienteId = 1;

  /// Qué hacer al tocar un aviso (abrir la sala): recibe el id y el nombre de la sala.
  void Function(int salaId, String titulo)? alTocar;
  DateTime _ultimoCambio = DateTime.fromMillisecondsSinceEpoch(0);

  static const _canal = AndroidNotificationDetails(
    'novedades_sala',
    'Novedades de la sala',
    channelDescription: 'Mensajes del equipo, propuestas de la IA y cambios del diagrama',
    importance: Importance.high,
    priority: Priority.high,
  );

  Future<void> iniciar() async {
    if (_listo) return;
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (respuesta) {
        final partes = (respuesta.payload ?? '').split('|');
        final salaId = int.tryParse(partes.first);
        if (salaId != null) alTocar?.call(salaId, partes.length > 1 ? partes.sublist(1).join('|') : 'Sala');
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    // El mismo canal lo usan las notificaciones push del servidor (FCM)
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      'novedades_sala',
      'Novedades de la sala',
      description: 'Mensajes del equipo, propuestas de la IA y cambios del diagrama',
      importance: Importance.high,
    ));
    await android?.requestNotificationsPermission();
    WidgetsBinding.instance.addObserver(this);
    _listo = true;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    enPrimerPlano = state == AppLifecycleState.resumed;
  }

  /// Muestra el aviso solo si la app no está a la vista. Los cambios del diagrama se agrupan:
  /// como mucho un aviso de cambios cada 30 segundos.
  Future<void> avisar(String titulo, String texto, {bool esCambio = false, int? salaId, String? sala}) async {
    if (!_listo || enPrimerPlano) return;
    if (esCambio) {
      final ahora = DateTime.now();
      if (ahora.difference(_ultimoCambio).inSeconds < 30) return;
      _ultimoCambio = ahora;
    }
    await _plugin.show(
      id: _siguienteId++,
      title: titulo,
      body: texto.length > 180 ? '${texto.substring(0, 177)}…' : texto,
      notificationDetails: const NotificationDetails(android: _canal),
      payload: salaId == null ? null : '$salaId|${sala ?? ''}',
    );
  }
}
