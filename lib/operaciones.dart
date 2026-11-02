/// Operaciones explícitas sobre el diagrama, iguales a las del servidor y la web
/// (backend/src/colaboracion/operacionesDiagrama.js): ponerNodo, moverNodo, quitarNodo,
/// ponerArista, quitarArista. Un borrado siempre llega como operación, así no queda un
/// elemento "fantasma" hasta la próxima sincronización completa.
library;

Map<String, dynamic> _mapa(dynamic x) => Map<String, dynamic>.from(x as Map);

/// Aplica las operaciones sobre las listas (las modifica en el lugar).
void aplicarOps(List<Map<String, dynamic>> nodos, List<Map<String, dynamic>> aristas, List ops) {
  for (final o in ops) {
    if (o is! Map) continue;
    switch (o['op']) {
      case 'ponerNodo':
        if (o['nodo'] is! Map) break;
        final nodo = _mapa(o['nodo']);
        final i = nodos.indexWhere((n) => n['id'] == nodo['id']);
        if (i >= 0) {
          nodos[i] = {...nodos[i], ...nodo};
        } else {
          nodos.add(nodo);
        }
      case 'moverNodo':
        final i = nodos.indexWhere((n) => n['id'] == o['id']);
        if (i >= 0 && o['position'] is Map) nodos[i] = {...nodos[i], 'position': _mapa(o['position'])};
      case 'quitarNodo':
        nodos.removeWhere((n) => n['id'] == o['id']);
        aristas.removeWhere((e) => e['source'] == o['id'] || e['target'] == o['id']);
      case 'ponerArista':
        if (o['arista'] is! Map) break;
        final arista = _mapa(o['arista']);
        // Una relación solo existe entre clases que existen (como en el servidor y la web)
        if (!nodos.any((n) => n['id'] == arista['source']) || !nodos.any((n) => n['id'] == arista['target'])) break;
        final i = aristas.indexWhere((e) => e['id'] == arista['id']);
        if (i >= 0) {
          aristas[i] = {...aristas[i], ...arista};
        } else {
          aristas.add(arista);
        }
      case 'quitarArista':
        aristas.removeWhere((e) => e['id'] == o['id']);
    }
  }
}
