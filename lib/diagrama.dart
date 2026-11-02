import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Dibujo del diagrama de clases (solo lectura) a partir de los nodos y aristas del tablero.
/// Las clases que acaban de cambiar se resaltan en amarillo unos segundos.

String _comoTexto(dynamic item, {bool metodo = false}) {
  if (item == null) return '';
  if (item is String) return item.trim();
  if (item is Map) {
    if (metodo && item['name'] != null) return '${item['name']}()${item['returnType'] != null ? ': ${item['returnType']}' : ''}';
    if (item['name'] != null && item['type'] != null) return '${item['name']}: ${item['type']}';
    if (item['name'] != null) return '${item['name']}';
  }
  return item.toString();
}

class CajaClase {
  CajaClase({required this.id, required this.rect, required this.nombre, required this.atributos, required this.metodos, required this.estereotipo, required this.esNota});
  final String id;
  final Rect rect;
  final String nombre;
  final List<String> atributos;
  final List<String> metodos;
  final String? estereotipo;
  final bool esNota;
}

const _estiloNombre = TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1D4ED8));
const _estiloMiembro = TextStyle(fontSize: 11, color: Color(0xFF111827));
const _estiloNota = TextStyle(fontSize: 11, color: Color(0xFF374151));
const double _linea = 15;

double _ancho(String texto, TextStyle estilo) {
  final tp = TextPainter(text: TextSpan(text: texto, style: estilo), textDirection: TextDirection.ltr, maxLines: 1)..layout();
  return tp.width;
}

/// Calcula el rectángulo de cada clase (posición del tablero, tamaño según su contenido).
List<CajaClase> calcularCajas(List<Map<String, dynamic>> nodos) {
  final cajas = <CajaClase>[];
  for (final n in nodos) {
    final datos = (n['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final pos = (n['position'] as Map?) ?? {};
    final x = (pos['x'] as num?)?.toDouble() ?? 0;
    final y = (pos['y'] as num?)?.toDouble() ?? 0;
    if (n['type'] == 'noteNode') {
      final texto = '${datos['text'] ?? ''}';
      final lineas = texto.split('\n');
      final ancho = math.min(260.0, math.max(140.0, lineas.map((l) => _ancho(l, _estiloNota)).fold<double>(0, math.max) + 24));
      final alto = 20 + lineas.fold<int>(0, (s, l) => s + 1 + (_ancho(l, _estiloNota) / (ancho - 24)).floor()) * _linea;
      cajas.add(CajaClase(id: '${n['id']}', rect: Rect.fromLTWH(x, y, ancho, alto), nombre: texto, atributos: const [], metodos: const [], estereotipo: datos['deIA'] == true ? 'ia' : null, esNota: true));
      continue;
    }
    if (n['type'] != 'classNode' || datos['isConnectionPoint'] == true) continue;
    final nombre = '${datos['className'] ?? 'Clase'}';
    final atributos = ((datos['attributes'] as List?) ?? []).map((a) => _comoTexto(a)).where((a) => a.isNotEmpty).toList();
    final metodos = ((datos['methods'] as List?) ?? []).map((m) => _comoTexto(m, metodo: true)).where((m) => m.isNotEmpty).toList();
    final estereotipo = datos['stereotype'] as String?;
    final anchos = [
      _ancho(nombre, _estiloNombre),
      ...atributos.map((a) => _ancho(a, _estiloMiembro)),
      ...metodos.map((m) => _ancho(m, _estiloMiembro)),
    ];
    final ancho = math.max(140.0, anchos.fold<double>(0, math.max) + 20);
    final alto = 30 + (estereotipo != null ? 13 : 0) + math.max(1, atributos.length) * _linea + 8 + (metodos.isEmpty ? 0 : metodos.length * _linea + 8);
    cajas.add(CajaClase(id: '${n['id']}', rect: Rect.fromLTWH(x, y, ancho, alto), nombre: nombre, atributos: atributos, metodos: metodos, estereotipo: estereotipo, esNota: false));
  }
  return cajas;
}

/// Límites de todo el diagrama, para encuadrarlo al abrir.
Rect limitesDe(List<CajaClase> cajas) {
  if (cajas.isEmpty) return const Rect.fromLTWH(0, 0, 400, 400);
  return cajas.map((c) => c.rect).reduce((a, b) => a.expandToInclude(b)).inflate(60);
}

/// Límites del zoom: con diagramas grandes hace falta alejarse mucho para verlo entero y acercarse
/// bastante para leer una clase.
const double escalaMinima = 0.05;
const double escalaMaxima = 6;

/// Por debajo de esta escala el texto de los miembros sería ilegible: se dibuja solo el nombre.
const double escalaCompacta = 0.5;

/// Escala que muestra todo el diagrama en la pantalla (por ancho y por alto, con un pequeño margen).
double escalaParaVer(Rect limites, Size pantalla) {
  if (limites.isEmpty || pantalla.isEmpty) return 1;
  final escala = math.min(pantalla.width / limites.width, pantalla.height / limites.height) * 0.95;
  return escala.clamp(escalaMinima, 1.5).toDouble();
}

/// La clase o nota que está en ese punto (coordenadas del tablero), la de arriba si se superponen.
CajaClase? cajaEn(List<CajaClase> cajas, Offset punto) {
  for (final c in cajas.reversed) {
    if (c.rect.contains(punto)) return c;
  }
  return null;
}

const _nombresRelacion = {
  'association': 'Asociación',
  'composition': 'Composición',
  'aggregation': 'Agregación',
  'generalization': 'Herencia',
  'inheritance': 'Herencia',
  'dependency': 'Dependencia',
  'realization': 'Realización',
  'implementation': 'Realización',
};

/// Relaciones de una clase en palabras, para la hoja de detalle ("Asociación con Producto (1 — *)").
List<String> relacionesDe(String id, List<CajaClase> cajas, List<Map<String, dynamic>> aristas) {
  final nombres = {for (final c in cajas) c.id: c.esNota ? 'nota' : c.nombre};
  final salida = <String>[];
  for (final e in aristas) {
    final datos = (e['data'] as Map?) ?? {};
    if (datos['isAssociationConnection'] == true) continue;
    final origen = '${e['source']}';
    final destino = '${e['target']}';
    if (origen != id && destino != id) continue;
    final otro = nombres[origen == id ? destino : origen];
    if (otro == null) continue;
    final tipo = '${datos['type'] ?? 'Association'}'.toLowerCase();
    final nombre = _nombresRelacion[tipo] ?? tipo;
    final esHerencia = nombre == 'Herencia' || nombre == 'Realización';
    final texto = esHerencia ? (origen == id ? '$nombre de $otro' : '$nombre: $otro la extiende') : '$nombre con $otro';
    final inicio = '${datos['startLabel'] ?? ''}'.trim();
    final fin = '${datos['endLabel'] ?? ''}'.trim();
    final mult = inicio.isEmpty && fin.isEmpty ? '' : ' (${origen == id ? inicio : fin} — ${origen == id ? fin : inicio})';
    final etiqueta = '${datos['label'] ?? ''}'.trim();
    salida.add('$texto$mult${etiqueta.isEmpty ? '' : ' «$etiqueta»'}');
  }
  return salida;
}

class PintorDiagrama extends CustomPainter {
  PintorDiagrama({required this.cajas, required this.aristas, required this.origen, required this.resaltadas, this.escala = 1, this.seleccionada});
  final List<CajaClase> cajas;
  final List<Map<String, dynamic>> aristas;
  final Offset origen;
  final Set<String> resaltadas;

  /// Escala actual del visor: alejado, cada clase muestra solo su nombre en letra legible.
  final double escala;

  /// Clase elegida en la búsqueda o tocada, con borde violeta.
  final String? seleccionada;

  bool get _compacto => escala < escalaCompacta;

  /// Punto del borde de la caja en la dirección del otro extremo.
  Offset _borde(Rect r, Offset hacia) {
    final c = r.center;
    final d = hacia - c;
    if (d.dx == 0 && d.dy == 0) return c;
    final tx = d.dx == 0 ? double.infinity : (r.width / 2) / d.dx.abs();
    final ty = d.dy == 0 ? double.infinity : (r.height / 2) / d.dy.abs();
    final t = math.min(tx, ty);
    return c + d * t;
  }

  void _punteada(Canvas canvas, Offset p1, Offset p2, Paint linea) {
    final d = p2 - p1;
    final largo = d.distance;
    for (double t = 0; t < largo; t += 10) {
      canvas.drawLine(p1 + d * (t / largo), p1 + d * (math.min(t + 5, largo) / largo), linea);
    }
  }

  void _texto(Canvas canvas, String texto, Offset en, TextStyle estilo, {double? ancho, bool centrado = false}) {
    final tp = TextPainter(text: TextSpan(text: texto, style: estilo), textDirection: TextDirection.ltr, maxLines: ancho == null ? 1 : 12, ellipsis: '…')
      ..layout(maxWidth: ancho ?? double.infinity);
    tp.paint(canvas, centrado ? en - Offset(tp.width / 2, 0) : en);
  }

  void _marcador(Canvas canvas, Offset punta, Offset desde, String tipo) {
    final dir = (punta - desde);
    final largo = dir.distance;
    if (largo == 0) return;
    final u = dir / largo;
    final n = Offset(-u.dy, u.dx);
    final trazo = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final relleno = Paint()..color = const Color(0xFF374151);
    final blanco = Paint()..color = Colors.white;
    switch (tipo) {
      case 'generalization':
      case 'inheritance':
      case 'implementation':
      case 'realization':
        final base = punta - u * 14;
        final tri = Path()
          ..moveTo(punta.dx, punta.dy)
          ..lineTo((base + n * 8).dx, (base + n * 8).dy)
          ..lineTo((base - n * 8).dx, (base - n * 8).dy)
          ..close();
        canvas.drawPath(tri, blanco);
        canvas.drawPath(tri, trazo);
      case 'composition':
      case 'aggregation':
        final medio = punta - u * 10;
        final fondo = punta - u * 20;
        final rombo = Path()
          ..moveTo(punta.dx, punta.dy)
          ..lineTo((medio + n * 6).dx, (medio + n * 6).dy)
          ..lineTo(fondo.dx, fondo.dy)
          ..lineTo((medio - n * 6).dx, (medio - n * 6).dy)
          ..close();
        canvas.drawPath(rombo, tipo == 'composition' ? relleno : blanco);
        canvas.drawPath(rombo, trazo);
      case 'dependency':
        final base = punta - u * 11;
        canvas.drawLine(punta, base + n * 6, trazo);
        canvas.drawLine(punta, base - n * 6, trazo);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(-origen.dx, -origen.dy);
    final porId = {for (final c in cajas) c.id: c};

    // Relaciones primero, para que queden debajo de las clases
    final aristasPorId = {for (final e in aristas) '${e['id']}': e};
    for (final e in aristas) {
      final a = porId['${e['source']}'];
      final b = porId['${e['target']}'];
      if (a == null || b == null) continue;
      final datos = (e['data'] as Map?) ?? {};
      final tipo = '${datos['type'] ?? 'Association'}'.toLowerCase();
      final linea = Paint()
        ..color = const Color(0xFF374151)
        ..strokeWidth = 1.5;
      // Clase de asociación: línea punteada de la clase al punto medio de su relación
      if (datos['isAssociationConnection'] == true) {
        final relacion = aristasPorId['${datos['parentRelationId']}'];
        final ra = porId['${relacion?['source']}'];
        final rb = porId['${relacion?['target']}'];
        if (ra != null && rb != null) {
          final medio = (_borde(ra.rect, rb.rect.center) + _borde(rb.rect, ra.rect.center)) / 2;
          _punteada(canvas, _borde(a.rect, medio), medio, linea);
        }
        continue;
      }
      final p1 = _borde(a.rect, b.rect.center);
      final p2 = _borde(b.rect, a.rect.center);
      if (tipo == 'implementation' || tipo == 'realization' || tipo == 'dependency' || a.esNota || b.esNota) {
        _punteada(canvas, p1, p2, linea);
      } else {
        canvas.drawLine(p1, p2, linea);
      }
      _marcador(canvas, p2, p1, tipo);
      // Alejado, las multiplicidades y los nombres de las relaciones no se alcanzan a leer
      if (_compacto) continue;
      final u = (p2 - p1).distance == 0 ? Offset.zero : (p2 - p1) / (p2 - p1).distance;
      final inicio = '${datos['startLabel'] ?? ''}';
      final fin = '${datos['endLabel'] ?? ''}';
      const estilo = TextStyle(fontSize: 10, color: Color(0xFF1F2937), fontWeight: FontWeight.w600);
      if (inicio.isNotEmpty) _texto(canvas, inicio, p1 + u * 16 + const Offset(4, -14), estilo);
      if (fin.isNotEmpty) _texto(canvas, fin, p2 - u * 26 + const Offset(4, -14), estilo);
      final etiqueta = '${datos['label'] ?? ''}';
      if (etiqueta.isNotEmpty) _texto(canvas, etiqueta, (p1 + p2) / 2 + const Offset(0, -14), const TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: Color(0xFF4B5563)), centrado: true);
    }

    for (final c in cajas) {
      final r = RRect.fromRectAndRadius(c.rect, const Radius.circular(8));
      final resaltada = resaltadas.contains(c.id);
      final elegida = c.id == seleccionada;
      if (c.esNota) {
        canvas.drawRRect(r, Paint()..color = c.estereotipo == 'ia' ? const Color(0xFFE0F2FE) : const Color(0xFFFFFACD));
        canvas.drawRRect(r, Paint()
          ..color = resaltada ? const Color(0xFFF59E0B) : const Color(0xFFD1D5DB)
          ..style = PaintingStyle.stroke
          ..strokeWidth = resaltada ? 3 : 1);
        if (!_compacto) _texto(canvas, c.nombre, c.rect.topLeft + const Offset(10, 8), _estiloNota, ancho: c.rect.width - 20);
        continue;
      }
      canvas.drawRRect(r.shift(const Offset(0, 2)), Paint()..color = const Color(0x22000000));
      canvas.drawRRect(r, Paint()..color = resaltada ? const Color(0xFFFEF3C7) : Colors.white);
      canvas.drawRRect(r, Paint()
        ..color = resaltada ? const Color(0xFFF59E0B) : const Color(0xFF3B82F6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = resaltada ? 3 : 1.6);
      if (elegida) {
        canvas.drawRRect(r.inflate(4 / escala), Paint()
          ..color = const Color(0xFF7C3AED)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 / escala);
      }
      if (_compacto) {
        _nombreCompacto(canvas, c);
        continue;
      }
      double y = c.rect.top + 7;
      if (c.estereotipo != null) {
        _texto(canvas, '«${c.estereotipo}»', Offset(c.rect.center.dx, y), const TextStyle(fontSize: 9, color: Color(0xFF6B7280)), centrado: true);
        y += 13;
      }
      _texto(canvas, c.nombre, Offset(c.rect.center.dx, y), c.estereotipo == 'abstract' ? _estiloNombre.copyWith(fontStyle: FontStyle.italic) : _estiloNombre, centrado: true);
      y += 21;
      final separador = Paint()
        ..color = const Color(0xFFBFDBFE)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(c.rect.left, y - 2), Offset(c.rect.right, y - 2), separador);
      for (final a in c.atributos) {
        _texto(canvas, a, Offset(c.rect.left + 10, y), _estiloMiembro);
        y += _linea;
      }
      if (c.atributos.isEmpty) y += _linea;
      if (c.metodos.isNotEmpty) {
        y += 4;
        canvas.drawLine(Offset(c.rect.left, y - 2), Offset(c.rect.right, y - 2), separador);
        for (final m in c.metodos) {
          _texto(canvas, m, Offset(c.rect.left + 10, y), _estiloMiembro);
          y += _linea;
        }
      }
    }
  }

  /// Vista alejada: solo el nombre, con una letra que en pantalla se ve de unos 12 px; si no entra,
  /// se achica hasta poco menos del doble del ancho de la caja, sin bajar de unos 8 px en pantalla.
  void _nombreCompacto(Canvas canvas, CajaClase c) {
    double tam = 12 / escala;
    TextPainter medir(double t) => TextPainter(
          text: TextSpan(text: c.nombre, style: _estiloNombre.copyWith(fontSize: t)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
    var tp = medir(tam);
    final maximo = c.rect.width * 1.8;
    if (tp.width > maximo) {
      tam = math.max(8 / escala, tam * maximo / tp.width);
      tp = medir(tam);
    }
    tp.paint(canvas, c.rect.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant PintorDiagrama old) => true;
}
