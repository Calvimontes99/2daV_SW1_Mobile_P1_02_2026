/// Junta lo que ya se ve con una respuesta del servidor que llega tarde (misma regla que la web,
/// frontend/src/utils/fusionHistorial.js):
///  - lo recibido en vivo mientras se esperaba gana;
///  - la respuesta reemplaza la versión vieja de un mismo id (trae datos completados después, como
///    el id de la propuesta de un mensaje de la IA) y agrega lo que faltaba;
///  - [descartarPrevios]: la respuesta reemplaza lo que había, salvo lo recibido en vivo.
library;

/// Cada sala tiene dos chats: 'equipo' (entre personas) e 'ia' (pedidos a la IA, sus respuestas y
/// avisos). El servidor manda el canal; para mensajes sin canal se usa su misma regla.
const canales = ['equipo', 'ia'];

String canalDe(Map<String, dynamic> m) {
  final canal = m['canal'];
  if (canal is String && canales.contains(canal)) return canal;
  final datos = m['datos'];
  return m['tipo'] != 'usuario' || (datos is Map && datos['paraIA'] == true) ? 'ia' : 'equipo';
}

/// ¿El texto le habla a la IA? (@IA en cualquier parte, como en el servidor)
bool mencionaALaIA(String texto) => RegExp(r'(^|\s)@ia\b', caseSensitive: false).hasMatch(texto);

/// Desde qué id pedir al reconectar (misma regla que la web): después del último mensaje, salvo
/// que un mensaje de la IA tenga su propuesta todavía sin id; entonces desde antes de él.
Object? cursorParaReanudar(List<Map<String, dynamic>> mensajes) {
  if (mensajes.isEmpty) return null;
  final ultimo = mensajes.last['id'];
  for (final m in mensajes) {
    final datos = m['datos'];
    final propuesta = datos is Map ? datos['propuesta'] : null;
    if (m['tipo'] == 'ia' && propuesta is Map && propuesta['id'] == null && m['id'] is num) {
      final anterior = (m['id'] as num).toInt() - 1;
      return ultimo is num && ultimo.toInt() < anterior ? ultimo : anterior;
    }
  }
  return ultimo;
}

List<Map<String, dynamic>> fusionarPorId(
  List<Map<String, dynamic>> previos,
  List<Map<String, dynamic>> respuesta,
  Set<Object?> vivos, {
  bool descartarPrevios = false,
}) {
  final porId = <Object?, Map<String, dynamic>>{};
  for (final x in previos) {
    if (!descartarPrevios || vivos.contains(x['id'])) porId[x['id']] = x;
  }
  for (final x in respuesta) {
    if (!vivos.contains(x['id']) || !porId.containsKey(x['id'])) porId[x['id']] = x;
  }
  final lista = porId.values.toList();
  lista.sort((a, b) => ((a['id'] as num?) ?? 0).compareTo((b['id'] as num?) ?? 0));
  return lista;
}
