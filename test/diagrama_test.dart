import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diagramador_movil/diagrama.dart';

Map<String, dynamic> clase(String id, String nombre, double x, double y, [List<String> atributos = const ['id: Long']]) => {
      'id': id,
      'type': 'classNode',
      'position': {'x': x, 'y': y},
      'data': {'className': nombre, 'attributes': atributos, 'methods': []},
    };

void main() {
  final cajas = calcularCajas([
    clase('cli', 'Cliente', 0, 0, ['id: Long', 'nombre: String']),
    clase('ped', 'Pedido', 400, 0),
    clase('art', 'Articulo', 0, 300),
    clase('pro', 'Producto', 400, 300),
  ]);
  final aristas = <Map<String, dynamic>>[
    {'id': 'r1', 'source': 'cli', 'target': 'ped', 'data': {'type': 'Association', 'startLabel': '1', 'endLabel': '*'}},
    {'id': 'r2', 'source': 'pro', 'target': 'art', 'data': {'type': 'Generalization'}},
    {'id': 'r3', 'source': 'ped', 'target': 'pro', 'data': {'type': 'Composition', 'startLabel': '1', 'endLabel': '1..*', 'label': 'contiene'}},
  ];

  test('para ver todo el diagrama se usa la escala que entra por ancho y por alto', () {
    final limites = limitesDe(cajas);
    final escala = escalaParaVer(limites, const Size(360, 600));
    expect(limites.width * escala, lessThanOrEqualTo(360));
    expect(limites.height * escala, lessThanOrEqualTo(600));
    // Un diagrama enorme se puede alejar hasta el mínimo, nunca menos
    expect(escalaParaVer(const Rect.fromLTWH(0, 0, 100000, 100000), const Size(360, 600)), escalaMinima);
    // Uno chico no se agranda más de la cuenta
    expect(escalaParaVer(const Rect.fromLTWH(0, 0, 100, 100), const Size(360, 600)), 1.5);
  });

  test('tocar dentro de una clase la encuentra; fuera, no hay ninguna', () {
    expect(cajaEn(cajas, const Offset(20, 20))?.nombre, 'Cliente');
    expect(cajaEn(cajas, const Offset(420, 320))?.nombre, 'Producto');
    expect(cajaEn(cajas, const Offset(300, 200)), isNull);
  });

  test('las relaciones de una clase se describen desde su lado', () {
    expect(relacionesDe('cli', cajas, aristas), ['Asociación con Pedido (1 — *)']);
    expect(relacionesDe('ped', cajas, aristas), ['Asociación con Cliente (* — 1)', 'Composición con Producto (1 — 1..*) «contiene»']);
    expect(relacionesDe('pro', cajas, aristas), ['Herencia de Articulo', 'Composición con Pedido (1..* — 1) «contiene»']);
    expect(relacionesDe('art', cajas, aristas), ['Herencia: Producto la extiende']);
  });
}
