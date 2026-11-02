import 'package:diagramador_movil/fusion.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> m(int id, [Map<String, dynamic>? datos]) => {'id': id, 'texto': 'mensaje $id', 'datos': ?datos};

void main() {
  test('una respuesta tardía no borra lo que llegó en vivo', () {
    final r = fusionarPorId([m(1), m(81)], [m(80)], {81});
    expect(r.map((x) => x['id']), [1, 80, 81]);
  });

  test('la respuesta actualiza datos de un mensaje ya conocido (tarjeta de la propuesta)', () {
    final previo = m(1, {'propuesta': {'estado': 'pendiente'}});
    final completo = m(1, {'propuesta': {'id': 7, 'estado': 'pendiente'}});
    final r = fusionarPorId([previo], [completo], {});
    expect((r.single['datos'] as Map)['propuesta']['id'], 7);
  });

  test('lo actualizado en vivo gana a la respuesta', () {
    final enVivo = m(1, {'propuesta': {'id': 7, 'estado': 'aceptada'}});
    final viejo = m(1, {'propuesta': {'id': 7, 'estado': 'pendiente'}});
    final r = fusionarPorId([enVivo], [viejo], {1});
    expect((r.single['datos'] as Map)['propuesta']['estado'], 'aceptada');
  });

  test('sin continuidad tras reconectar no queda un hueco: se empieza de nuevo desde lo último', () {
    final previos = List.generate(80, (i) => m(i + 1));
    final ultimos = List.generate(80, (i) => m(201 + i));
    final r = fusionarPorId(previos, ultimos, {}, descartarPrevios: true);
    expect(r.first['id'], 201, reason: 'Cargar anteriores sigue desde 201 hacia atrás');
    expect(r.length, 80);
  });

  test('reanudar trae lo posterior y se une sin huecos', () {
    final previos = List.generate(80, (i) => m(i + 1));
    final posteriores = List.generate(200, (i) => m(81 + i));
    final r = fusionarPorId(previos, posteriores, {});
    final ids = r.map((x) => x['id'] as int).toList();
    expect(ids.first, 1);
    expect(ids.last, 280);
    expect(ids.length, 280);
  });

  test('al reconectar se vuelve a pedir un mensaje de la IA con la propuesta todavía sin id', () {
    final mensajes = [
      m(98),
      {'id': 100, 'tipo': 'ia', 'datos': {'propuesta': <String, dynamic>{'estado': 'pendiente'}}},
      m(101),
    ];
    expect(cursorParaReanudar(mensajes), 99);
    ((mensajes[1]['datos'] as Map)['propuesta'] as Map)['id'] = 7;
    expect(cursorParaReanudar(mensajes), 101);
    expect(cursorParaReanudar([]), isNull);
  });

  test('cada mensaje va a su chat: equipo o IA', () {
    expect(canalDe({'tipo': 'usuario', 'texto': 'hola'}), 'equipo');
    expect(canalDe({'tipo': 'usuario', 'datos': {'paraIA': true}}), 'ia');
    expect(canalDe({'tipo': 'ia'}), 'ia');
    expect(canalDe({'tipo': 'sistema'}), 'ia');
    expect(canalDe({'tipo': 'usuario', 'canal': 'ia'}), 'ia');
    expect(mencionaALaIA('oye @IA revisa'), isTrue);
    expect(mencionaALaIA('correo@ia.com'), isFalse);
  });
}
