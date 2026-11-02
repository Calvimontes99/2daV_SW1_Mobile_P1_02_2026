import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:diagramador_movil/api.dart';
import 'package:diagramador_movil/pantalla_sala.dart';
import 'package:diagramador_movil/tiempo_real.dart';

/// Diagrama grande (30 clases en grilla, ~2400 × 2000): sin zoom no se lee nada en un teléfono.
SalaEnVivo salaGrande() {
  final sala = SalaEnVivo(Sesion(servidor: 'http://localhost', token: 't', nombre: 'Prueba', id: 1, email: 'p@x.com'), 1);
  sala.nodos = [
    for (var i = 0; i < 30; i++)
      {
        'id': 'c$i',
        'type': 'classNode',
        'position': {'x': (i % 6) * 400.0, 'y': (i ~/ 6) * 400.0},
        'data': {'className': 'Clase$i', 'attributes': ['id: Long', 'nombre: String'], 'methods': []},
      },
  ];
  sala.aristas = [
    {'id': 'r1', 'source': 'c7', 'target': 'c8', 'data': {'type': 'Association', 'startLabel': '1', 'endLabel': '*'}},
  ];
  return sala;
}

int porcentaje(WidgetTester tester) {
  final chip = tester.widget<Text>(find.descendant(of: find.byType(Chip), matching: find.byType(Text)));
  return int.parse(RegExp(r'(\d+) %').firstMatch(chip.data!)!.group(1)!);
}

void main() {
  testWidgets('con un diagrama grande se puede acercar, buscar una clase y ver su detalle', (tester) async {
    tester.view.physicalSize = const Size(720, 1280);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: VistaDiagrama(sala: salaGrande()))));
    await tester.pumpAndSettle();

    // Al abrir se ve todo el diagrama, bien por debajo del 100 %
    final inicial = porcentaje(tester);
    expect(inicial, lessThan(20));

    // Los botones acercan (antes el zoom quedaba trabado por la escala mal medida)
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byTooltip('Acercar'));
      await tester.pumpAndSettle();
    }
    expect(porcentaje(tester), closeTo(inicial * 3.375, 2));
    await tester.tap(find.byTooltip('Alejar'));
    await tester.pumpAndSettle();
    expect(porcentaje(tester), closeTo(inicial * 2.25, 2));

    // Doble toque: acerca donde se tocó; otro doble toque vuelve a ver todo
    final centro = tester.getCenter(find.byType(InteractiveViewer));
    await tester.tapAt(centro);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centro);
    await tester.pumpAndSettle();
    expect(porcentaje(tester), 160);
    await tester.tapAt(centro);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centro);
    await tester.pumpAndSettle();
    expect(porcentaje(tester), inicial);

    // Buscar una clase lleva el visor hasta ella
    await tester.tap(find.byTooltip('Buscar una clase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Clase7');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Clase7'));
    await tester.pumpAndSettle();
    expect(porcentaje(tester), 130);

    // Tocarla (quedó en el centro) abre su detalle con los miembros y las relaciones
    await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    expect(find.text('Clase7'), findsOneWidget);
    expect(find.text('• nombre: String'), findsOneWidget);
    expect(find.text('• Asociación con Clase8 (1 — *)'), findsOneWidget);
  });
}
