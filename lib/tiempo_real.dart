import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api.dart';
import 'fusion.dart';
import 'operaciones.dart';

/// Conexión en vivo con una sala: el diagrama, el chat, las propuestas de la IA y el historial.
/// Usa los mismos eventos de Socket.IO que la web, así el móvil ve todo al instante.
class SalaEnVivo extends ChangeNotifier {
  SalaEnVivo(this.sesion, this.salaId);

  final Sesion sesion;
  final int salaId;
  io.Socket? _socket;

  List<Map<String, dynamic>> nodos = [];
  List<Map<String, dynamic>> aristas = [];
  final List<Map<String, dynamic>> mensajes = [];
  final Map<int, Map<String, dynamic>> propuestas = {};
  final List<Map<String, dynamic>> cambios = [];
  Map<String, dynamic> estadoIA = {'ocupada': false};
  String? bienvenida;
  bool conectado = false;
  /// Por chat ('equipo' | 'ia'): si quedan mensajes anteriores sin cargar.
  final Map<String, bool> anteriores = {'equipo': false, 'ia': false};
  bool get hayAnteriores => anteriores.values.any((x) => x);
  // Lo que llegó en vivo desde que se pidió el historial: una respuesta tardía no lo pisa
  final Set<Object?> _vivosMensajes = {};
  final Set<Object?> _vivosPropuestas = {};
  final Set<Object?> _vivosCambios = {};
  // Hora del servidor de la última respuesta del chat: al reconectar se piden también los mensajes
  // que cambiaron desde entonces (p. ej. el id de la propuesta que la IA agrega después)
  Object? _marca;
  String? error;

  /// Clases que acaban de cambiar (se resaltan unos segundos en el diagrama).
  final Map<String, DateTime> resaltadas = {};

  /// Avisos para notificar cuando la app está en segundo plano.
  final _avisos = StreamController<({String titulo, String texto})>.broadcast();
  Stream<({String titulo, String texto})> get avisos => _avisos.stream;

  void conectar() {
    final socket = io.io(
      sesion.servidor,
      io.OptionBuilder().setTransports(['websocket']).setAuth({'token': sesion.token}).enableForceNew().disableAutoConnect().build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      socket.emitWithAck('unirseSala', {'salaId': salaId, 'usuario': {'id': sesion.id, 'name': sesion.nombre, 'email': sesion.email}}, ack: (ack) {
        conectado = ack is Map && ack['ok'] == true;
        error = conectado ? null : 'No se pudo entrar a la sala.';
        notifyListeners();
        if (conectado) _cargarChat();
      });
    });
    socket.onDisconnect((_) {
      conectado = false;
      notifyListeners();
    });
    socket.onConnectError((e) {
      conectado = false;
      error = 'Sin conexión con el servidor.';
      notifyListeners();
    });
    // Te quitaron del tablero o lo borraron
    socket.on('accesoRevocado', (d) {
      conectado = false;
      error = d is Map ? (d['mensaje'] as String? ?? 'Ya no tienes acceso a este tablero.') : 'Ya no tienes acceso a este tablero.';
      notifyListeners();
      socket.disconnect();
    });
    socket.on('errorSincronizacion', (d) {
      error = d is Map ? d['message'] as String? : null;
      notifyListeners();
    });

    // Diagrama: estado completo y cambios parciales (mismos eventos que la web)
    void ponerEstado(dynamic estado) {
      if (estado is! Map) return;
      nodos = List<Map<String, dynamic>>.from((estado['nodes'] as List? ?? []).map((n) => Map<String, dynamic>.from(n as Map)));
      aristas = List<Map<String, dynamic>>.from((estado['edges'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
      notifyListeners();
    }

    socket.on('estadoInicial', (d) => ponerEstado(d is Map ? d['state'] : null));
    socket.on('xmlActualizado', (d) => ponerEstado(d is Map ? d['nuevoEstado'] : null));
    socket.on('diagramaActualizado', (d) => ponerEstado(d is Map && d['data'] is Map ? d['data']['state'] : null));
    // Cambios de los demás como operaciones explícitas (crear, mover, borrar...)
    socket.on('operaciones', (d) {
      if (d is! Map || '${d['salaId']}' != '$salaId' || d['ops'] is! List) return;
      final ops = d['ops'] as List;
      aplicarOps(nodos, aristas, ops);
      for (final o in ops) {
        final id = o is Map ? (o['id'] ?? (o['nodo'] is Map ? o['nodo']['id'] : null)) : null;
        if (id is String && o['op'] != 'moverNodo') resaltadas[id] = DateTime.now();
      }
      notifyListeners();
    });

    socket.on('chat:nuevo', (d) {
      if (d is! Map) return;
      final m = Map<String, dynamic>.from(d);
      _vivosMensajes.add(m['id']);
      _ponerMensaje(m);
      final propio = m['tipo'] == 'usuario' && (m['autorId'] as num?)?.toInt() == sesion.id;
      if (!propio && m['tipo'] != 'sistema') {
        _avisos.add((titulo: m['tipo'] == 'ia' ? '🤖 IA' : '${m['autorNombre']}', texto: '${m['texto']}'));
      }
    });
    socket.on('chat:actualizado', (d) {
      if (d is! Map) return;
      final m = Map<String, dynamic>.from(d);
      _vivosMensajes.add(m['id']);
      _ponerMensaje(m);
    });
    socket.on('propuesta:nueva', (d) {
      if (d is! Map) return;
      final p = Map<String, dynamic>.from(d);
      _vivosPropuestas.add(p['id']);
      propuestas[(p['id'] as num).toInt()] = p;
      _avisos.add((titulo: '🤖 Propuesta de la IA', texto: '${(p['resumen'] as List?)?.length ?? 0} cambios pedidos por ${p['pedidoPorNombre']}'));
      notifyListeners();
    });
    socket.on('propuesta:actualizada', (d) {
      if (d is! Map) return;
      final p = Map<String, dynamic>.from(d);
      _vivosPropuestas.add(p['id']);
      propuestas[(p['id'] as num).toInt()] = p;
      notifyListeners();
    });
    socket.on('ia:estado', (d) {
      if (d is Map) estadoIA = Map<String, dynamic>.from(d);
      notifyListeners();
    });
    socket.on('historial:nuevo', (d) {
      if (d is! Map) return;
      final c = Map<String, dynamic>.from(d);
      _vivosCambios.add(c['id']);
      if (!cambios.any((x) => x['id'] == c['id'])) cambios.add(c);
      final id = c['elementoId'];
      if (id is String) resaltadas[id] = DateTime.now();
      final quien = c['esIA'] == true ? 'La IA' : '${c['autorNombre']}';
      if ((c['autorId'] as num?)?.toInt() != sesion.id || c['esIA'] == true) {
        _avisos.add((titulo: 'Cambio en el diagrama', texto: '$quien ${c['resumen']}'));
      }
      notifyListeners();
    });
    socket.on('chat:bienvenida', (d) {
      if (d is Map) bienvenida = d['texto'] as String?;
      notifyListeners();
    });

    socket.connect();
  }

  void _ponerMensaje(Map<String, dynamic> m) {
    final i = mensajes.indexWhere((x) => x['id'] == m['id']);
    if (i >= 0) {
      mensajes[i] = m;
    } else {
      mensajes.add(m);
    }
    notifyListeners();
  }

  /// Carga (o completa, al reconectar) el chat y el historial. Si ya había mensajes, se piden solo
  /// los posteriores al último: así no queda un hueco entre lo viejo y lo nuevo.
  void _cargarChat() {
    _vivosMensajes.clear();
    _vivosPropuestas.clear();
    _vivosCambios.clear();
    _pedirMensajes(cursorParaReanudar(mensajes));
    _pedirCambios(cambios.isNotEmpty ? cambios.last['id'] : null);
  }

  void _pedirMensajes(Object? despuesDe) {
    final actualizadosDesde = despuesDe != null ? _marca : null;
    _socket?.emitWithAck('chat:historial', {'salaId': salaId, 'despuesDe': ?despuesDe, 'actualizadosDesde': ?actualizadosDesde}, ack: (r) {
      if (r is! Map || r['ok'] != true) return;
      final reanudacion = r['reanudacion'] == true;
      if (r['marca'] != null) _marca = r['marca'];
      // Faltan demasiados: se empieza de nuevo desde los últimos ("Cargar anteriores" sigue desde ahí)
      if (reanudacion && r['completo'] != true) {
        _pedirMensajes(null);
        return;
      }
      final lista = List<Map<String, dynamic>>.from((r['mensajes'] as List? ?? []).map((m) => Map<String, dynamic>.from(m as Map)));
      final juntos = fusionarPorId(mensajes, lista, _vivosMensajes, descartarPrevios: !reanudacion);
      mensajes
        ..clear()
        ..addAll(juntos);
      if (!reanudacion) {
        final porCanal = r['hayAnteriores'];
        for (final canal in canales) {
          anteriores[canal] = porCanal is Map
              ? porCanal[canal] == true
              : lista.where((m) => canalDe(m) == canal).length >= 80;
        }
      }
      for (final p in (r['propuestas'] as List? ?? [])) {
        final mapa = Map<String, dynamic>.from(p as Map);
        // La respuesta actualiza las propuestas que ya se veían, salvo las cambiadas en vivo
        if (!_vivosPropuestas.contains(mapa['id'])) propuestas[(mapa['id'] as num).toInt()] = mapa;
      }
      if (r['ia'] is Map) estadoIA = Map<String, dynamic>.from(r['ia'] as Map);
      notifyListeners();
    });
  }

  void _pedirCambios(Object? despuesDe) {
    _socket?.emitWithAck('historial:listar', {'salaId': salaId, 'despuesDe': ?despuesDe}, ack: (r) {
      if (r is! Map || r['ok'] != true) return;
      final reanudacion = r['reanudacion'] == true;
      if (reanudacion && r['completo'] != true) {
        _pedirCambios(null);
        return;
      }
      final lista = List<Map<String, dynamic>>.from((r['cambios'] as List? ?? []).map((c) => Map<String, dynamic>.from(c as Map)));
      final juntos = fusionarPorId(cambios, lista, _vivosCambios, descartarPrevios: !reanudacion);
      cambios
        ..clear()
        ..addAll(juntos);
      notifyListeners();
    });
  }

  /// Mensajes más viejos de un chat ('equipo' | 'ia') que el primero que se ve de ese chat; sin
  /// canal, de los dos.
  Future<void> cargarAnteriores([String? canal]) async {
    final deCanal = canal == null ? mensajes : mensajes.where((m) => canalDe(m) == canal).toList();
    if (deCanal.isEmpty || _socket == null) return;
    final c = Completer<void>();
    _socket!.emitWithAck('chat:anteriores', {'salaId': salaId, 'antesDe': deCanal.first['id'], 'canal': ?canal}, ack: (r) {
      if (r is Map && r['ok'] == true) {
        final viejos = List<Map<String, dynamic>>.from((r['mensajes'] as List).map((m) => Map<String, dynamic>.from(m as Map)))
            .where((m) => !mensajes.any((x) => x['id'] == m['id']))
            .toList();
        // Ordenados por id: los anteriores de un chat pueden quedar entre mensajes del otro
        final juntos = fusionarPorId(mensajes, viejos, const {});
        mensajes
          ..clear()
          ..addAll(juntos);
        for (final k in canal == null ? canales : [canal]) {
          anteriores[k] = r['hayMas'] == true;
        }
        notifyListeners();
      }
      if (!c.isCompleted) c.complete();
    });
    return c.future.timeout(const Duration(seconds: 15), onTimeout: () {});
  }

  Future<String?> enviar(String texto, {bool paraIA = false}) {
    final c = Completer<String?>();
    _socket?.emitWithAck('chat:enviar', {'salaId': salaId, 'texto': texto, 'paraIA': paraIA}, ack: (r) {
      c.complete(r is Map && r['ok'] == true ? null : (r is Map ? r['mensaje'] as String? : 'No se envió.'));
    });
    if (_socket == null) c.complete('Sin conexión.');
    return c.future.timeout(const Duration(seconds: 15), onTimeout: () => 'El servidor no respondió.');
  }

  Future<String?> decidir(int propuestaId, String decision) {
    final c = Completer<String?>();
    _socket?.emitWithAck('propuesta:decidir', {'salaId': salaId, 'propuestaId': propuestaId, 'decision': decision}, ack: (r) {
      c.complete(r is Map && r['ok'] == true ? null : (r is Map ? r['mensaje'] as String? : 'No se aplicó.'));
    });
    if (_socket == null) c.complete('Sin conexión.');
    return c.future.timeout(const Duration(seconds: 20), onTimeout: () => 'El servidor no respondió.');
  }

  @override
  void dispose() {
    _socket?.dispose();
    _avisos.close();
    super.dispose();
  }
}
