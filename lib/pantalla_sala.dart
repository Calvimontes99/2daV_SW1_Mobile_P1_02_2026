import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'diagrama.dart';
import 'notificaciones.dart';
import 'fusion.dart';
import 'tiempo_real.dart';

/// Una sala en el móvil: el diagrama en vivo, el chat del equipo con la IA y el historial.
class PantallaSala extends StatefulWidget {
  const PantallaSala({super.key, required this.sesion, required this.salaId, required this.titulo});
  final Sesion sesion;
  final int salaId;
  final String titulo;
  @override
  State<PantallaSala> createState() => _PantallaSalaState();
}

class _PantallaSalaState extends State<PantallaSala> {
  late final SalaEnVivo sala;
  StreamSubscription? _avisos;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    sala = SalaEnVivo(widget.sesion, widget.salaId)..conectar();
    _avisos = sala.avisos.listen((a) => Notificaciones.instancia.avisar(
          '${widget.titulo}: ${a.titulo}',
          a.texto,
          esCambio: a.titulo == 'Cambio en el diagrama',
          salaId: widget.salaId,
          sala: widget.titulo,
        ));
    // Repinta cada segundo para apagar el resaltado de las clases que cambiaron
    _reloj = Timer.periodic(const Duration(seconds: 1), (_) {
      if (sala.resaltadas.isNotEmpty) {
        sala.resaltadas.removeWhere((_, cuando) => DateTime.now().difference(cuando).inSeconds > 6);
        if (mounted) setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _reloj?.cancel();
    _avisos?.cancel();
    sala.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: ListenableBuilder(
        listenable: sala,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.titulo, overflow: TextOverflow.ellipsis),
              Text(
                sala.conectado
                    ? (sala.estadoIA['ocupada'] == true ? '🤖 La IA está atendiendo a ${sala.estadoIA['atendiendoA']}…' : 'En vivo')
                    : (sala.error ?? 'Conectando…'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
            bottom: const TabBar(tabs: [
              Tab(icon: Icon(Icons.account_tree_outlined), text: 'Diagrama'),
              Tab(icon: Icon(Icons.forum_outlined), text: 'Chat'),
              Tab(icon: Icon(Icons.history), text: 'Quién hizo qué'),
            ]),
          ),
          body: TabBarView(
            physics: const NeverScrollableScrollPhysics(),
            children: [
              VistaDiagrama(sala: sala),
              VistaChat(sala: sala),
              VistaHistorial(sala: sala),
            ],
          ),
        ),
      ),
    );
  }
}

class VistaDiagrama extends StatefulWidget {
  const VistaDiagrama({super.key, required this.sala});
  final SalaEnVivo sala;
  @override
  State<VistaDiagrama> createState() => _VistaDiagramaState();
}

class _VistaDiagramaState extends State<VistaDiagrama> with SingleTickerProviderStateMixin {
  final _transformacion = TransformationController();
  late final AnimationController _animacion = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
  Animation<Matrix4>? _destino;
  bool _encuadrado = false;
  Size _pantalla = Size.zero;
  Offset? _dobleToque;
  String? _seleccionada;

  @override
  void initState() {
    super.initState();
    _animacion.addListener(() {
      if (_destino != null) _transformacion.value = _destino!.value;
    });
  }

  @override
  void dispose() {
    _animacion.dispose();
    _transformacion.dispose();
    super.dispose();
  }

  double get _escala => _transformacion.value.getMaxScaleOnAxis();

  /// Transformación que deja ese punto del lienzo en el centro de la pantalla con esa escala.
  /// La escala va también en Z: InteractiveViewer mide la escala con el mayor de los tres ejes, y con
  /// Z en 1 creía estar al 100 % aunque se viera al 20 %, así que el pellizco no dejaba acercar.
  Matrix4 _centradoEn(Offset punto, double escala) {
    final dx = _pantalla.width / 2 - punto.dx * escala;
    final dy = _pantalla.height / 2 - punto.dy * escala;
    return Matrix4(escala, 0, 0, 0, 0, escala, 0, 0, 0, 0, escala, 0, dx, dy, 0, 1);
  }

  void _animarA(Matrix4 destino) {
    _destino = Matrix4Tween(begin: _transformacion.value, end: destino)
        .animate(CurvedAnimation(parent: _animacion, curve: Curves.easeOutCubic));
    _animacion.forward(from: 0);
  }

  void _encuadrar(Rect limites, {bool animado = true}) {
    final destino = _centradoEn(limites.size.center(Offset.zero), escalaParaVer(limites, _pantalla));
    if (animado) {
      _animarA(destino);
    } else {
      _transformacion.value = destino;
    }
  }

  /// Acerca o aleja manteniendo fijo el centro de la pantalla.
  void _zoom(double factor) {
    final centro = _transformacion.toScene(_pantalla.center(Offset.zero));
    _animarA(_centradoEn(centro, (_escala * factor).clamp(escalaMinima, escalaMaxima).toDouble()));
  }

  /// Doble toque: acerca donde se tocó; si ya está cerca, vuelve a ver todo.
  void _alDobleToque(Rect limites) {
    final punto = _dobleToque;
    if (punto == null) return;
    if (_escala >= 1.2) {
      _encuadrar(limites);
    } else {
      _animarA(_centradoEn(punto, 1.6));
    }
  }

  void _irAClase(CajaClase caja, Rect limites) {
    setState(() => _seleccionada = caja.id);
    _animarA(_centradoEn(caja.rect.center - limites.topLeft, 1.3));
  }

  void _verDetalle(CajaClase caja, List<CajaClase> cajas) {
    setState(() => _seleccionada = caja.id);
    final relaciones = relacionesDe(caja.id, cajas, widget.sala.aristas);
    final tema = Theme.of(context).textTheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.45,
        maxChildSize: 0.9,
        builder: (context, desplazamiento) => ListView(
          controller: desplazamiento,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            if (caja.estereotipo != null && !caja.esNota) Text('«${caja.estereotipo}»', style: tema.bodySmall),
            Text(caja.esNota ? 'Nota' : caja.nombre, style: tema.titleLarge),
            if (caja.esNota) Padding(padding: const EdgeInsets.only(top: 8), child: Text(caja.nombre, style: tema.bodyLarge)),
            if (!caja.esNota) ...[
              _seccion('Atributos', caja.atributos, tema, vacio: 'Sin atributos'),
              if (caja.metodos.isNotEmpty) _seccion('Métodos', caja.metodos, tema),
              _seccion('Relaciones', relaciones, tema, vacio: 'No está relacionada con otras clases'),
            ],
          ],
        ),
      ),
    );
  }

  Widget _seccion(String titulo, List<String> items, TextTheme tema, {String? vacio}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: tema.titleSmall),
        const SizedBox(height: 4),
        if (items.isEmpty && vacio != null) Text(vacio, style: tema.bodyMedium?.copyWith(color: Colors.grey)),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('• $item', style: tema.bodyLarge),
          ),
      ]),
    );
  }

  /// Lista de clases con filtro: elegir una lleva el visor hasta ella.
  Future<void> _buscarClase(List<CajaClase> cajas, Rect limites) async {
    final clases = cajas.where((c) => !c.esNota).toList()..sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    final elegida = await showModalBottomSheet<CajaClase>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        var filtro = '';
        return StatefulBuilder(builder: (context, actualizar) {
          final visibles = clases.where((c) => c.nombre.toLowerCase().contains(filtro.toLowerCase())).toList();
          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar clase', border: OutlineInputBorder()),
                  onChanged: (v) => actualizar(() => filtro = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: visibles.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: const Icon(Icons.crop_square),
                    title: Text(visibles[i].nombre),
                    subtitle: Text('${visibles[i].atributos.length} atributos'),
                    onTap: () => Navigator.pop(context, visibles[i]),
                  ),
                ),
              ),
            ]),
          );
        });
      },
    );
    if (elegida != null) _irAClase(elegida, limites);
  }

  @override
  Widget build(BuildContext context) {
    final cajas = calcularCajas(widget.sala.nodos);
    final limites = limitesDe(cajas);
    if (cajas.isEmpty) {
      return Center(child: Text(widget.sala.conectado ? 'El diagrama está vacío.' : 'Cargando el diagrama…'));
    }
    return LayoutBuilder(builder: (context, medidas) {
      // Con el teclado abierto (buscar clase) la pantalla se achica: se mide sin él para que, al
      // cerrarlo, el centrado no quede corrido hacia arriba
      _pantalla = Size(medidas.maxWidth, medidas.maxHeight + MediaQuery.viewInsetsOf(context).bottom);
      if (!_encuadrado) {
        _encuadrado = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _encuadrar(limites, animado: false));
      }
      return Stack(children: [
        InteractiveViewer(
          transformationController: _transformacion,
          constrained: false,
          minScale: escalaMinima,
          maxScale: escalaMaxima,
          boundaryMargin: const EdgeInsets.all(double.infinity),
          child: GestureDetector(
            onTapUp: (d) {
              final caja = cajaEn(cajas, d.localPosition + limites.topLeft);
              if (caja != null) _verDetalle(caja, cajas);
            },
            onDoubleTapDown: (d) => _dobleToque = d.localPosition,
            onDoubleTap: () => _alDobleToque(limites),
            // La escala cambia con los gestos: alejado se dibuja solo el nombre de cada clase
            child: ListenableBuilder(
              listenable: _transformacion,
              builder: (context, _) => CustomPaint(
                size: limites.size,
                painter: PintorDiagrama(
                  cajas: cajas,
                  aristas: widget.sala.aristas,
                  origen: limites.topLeft,
                  resaltadas: widget.sala.resaltadas.keys.toSet(),
                  escala: _escala,
                  seleccionada: _seleccionada,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FloatingActionButton.small(
              heroTag: 'buscar',
              tooltip: 'Buscar una clase',
              onPressed: () => _buscarClase(cajas, limites),
              child: const Icon(Icons.search),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'acercar',
              tooltip: 'Acercar',
              onPressed: () => _zoom(1.5),
              child: const Icon(Icons.add),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'alejar',
              tooltip: 'Alejar',
              onPressed: () => _zoom(1 / 1.5),
              child: const Icon(Icons.remove),
            ),
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'encuadrar',
              tooltip: 'Ver todo el diagrama',
              onPressed: () => _encuadrar(limites),
              child: const Icon(Icons.fit_screen),
            ),
          ]),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: ListenableBuilder(
            listenable: _transformacion,
            builder: (context, _) => Chip(
              visualDensity: VisualDensity.compact,
              label: Text('${cajas.where((c) => !c.esNota).length} clases · ${widget.sala.aristas.length} relaciones · ${(_escala * 100).round()} %'),
            ),
          ),
        ),
        Positioned(
          left: 12,
          top: 8,
          right: 12,
          child: IgnorePointer(
            child: Text(
              'Pellizca o usa + y − para acercar · toca una clase para ver sus detalles',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
            ),
          ),
        ),
      ]);
    });
  }
}

const _colorGravedad = {'error': Color(0xFFFEE2E2), 'aviso': Color(0xFFFEF3C7), 'sugerencia': Color(0xFFDBEAFE)};

class VistaChat extends StatefulWidget {
  const VistaChat({super.key, required this.sala});
  final SalaEnVivo sala;
  @override
  State<VistaChat> createState() => _VistaChatState();
}

class _VistaChatState extends State<VistaChat> {
  final _texto = TextEditingController();
  final _desplazamiento = ScrollController();
  bool _enviando = false;
  int _vistos = 0;
  // Chat que se ve: 'equipo' (entre personas) o 'ia' (la IA compartida de la sala)
  String _canal = 'equipo';

  Future<void> _mandar() async {
    final t = _texto.text.trim();
    if (t.isEmpty || _enviando) return;
    // En el chat del equipo, mencionar a @IA también le pide algo (va al chat de la IA)
    final paraIA = _canal == 'ia' || mencionaALaIA(t);
    setState(() => _enviando = true);
    final error = await widget.sala.enviar(t, paraIA: paraIA);
    if (!mounted) return;
    setState(() {
      _enviando = false;
      if (error == null && paraIA) _canal = 'ia';
    });
    if (error == null) {
      _texto.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  Future<void> _decidir(int id, String decision) async {
    final error = await widget.sala.decidir(id, decision);
    if (!mounted) return;
    if (error != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
  }

  String _hora(String? iso) {
    final d = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
    return d == null ? '' : '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  Widget _propuesta(Map<String, dynamic> p) {
    final estado = '${p['estado']}';
    final resumen = List<String>.from((p['resumen'] as List? ?? []).map((x) => '$x'));
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFDDD6FE))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Propuesta: ${resumen.length} cambios · $estado', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        for (final r in resumen) Text('• $r', style: const TextStyle(fontSize: 12)),
        if (estado == 'pendiente')
          Row(children: [
            FilledButton(onPressed: () => _decidir((p['id'] as num).toInt(), 'aceptar'), child: const Text('Aceptar')),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: () => _decidir((p['id'] as num).toInt(), 'rechazar'), child: const Text('Rechazar')),
          ])
        else if (p['decididoPorNombre'] != null)
          Text('Por ${p['decididoPorNombre']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ]),
    );
  }

  Widget _mensaje(Map<String, dynamic> m) {
    final tipo = m['tipo'];
    if (tipo == 'sistema') {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 24), child: Text('${m['texto']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black54)));
    }
    final esIA = tipo == 'ia';
    final propio = !esIA && (m['autorId'] as num?)?.toInt() == widget.sala.sesion.id;
    final datos = (m['datos'] as Map?)?.cast<String, dynamic>() ?? {};
    final propuestaId = (datos['propuesta'] as Map?)?['id'];
    final propuesta = propuestaId is num ? widget.sala.propuestas[propuestaId.toInt()] : null;
    final observaciones = (datos['observaciones'] as List?) ?? [];
    final ideas = (datos['ideas'] as List?) ?? [];
    return Align(
      alignment: propio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.86),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: esIA ? const Color(0xFFF5F3FF) : propio ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: esIA ? const Color(0xFFDDD6FE) : const Color(0xFFE5E7EB)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            '${esIA ? (datos['proveedor'] == 'IA local' ? '💻 IA local' : '🤖 IA') : propio ? 'Tú' : m['autorNombre']} · ${_hora((datos['escritoEn'] ?? m['creadoEn']) as String?)}${esIA && datos['proveedor'] != null && datos['proveedor'] != 'IA local' ? ' · ${datos['proveedor']}' : ''}${datos['sinConexion'] == true ? ' · sin conexión' : ''}',
            style: TextStyle(fontSize: 11, color: propio ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text('${m['texto']}'.replaceAll('**', '').replaceAll('`', ''), style: TextStyle(color: propio ? Colors.white : Colors.black87)),
          for (final o in observaciones)
            if (o is Map)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: _colorGravedad[o['gravedad']] ?? const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(6)),
                child: Text('${o['clase']}: ${o['texto']}', style: const TextStyle(fontSize: 12)),
              ),
          for (final i in ideas)
            if (i is Map)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: const Color(0xFFE0F2FE), borderRadius: BorderRadius.circular(6)),
                child: Text('💡 ${i['titulo']}: ${i['texto']}', style: const TextStyle(fontSize: 12)),
              ),
          if (propuesta != null) _propuesta(propuesta),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final deIA = _canal == 'ia';
    final mensajes = widget.sala.mensajes.where((m) => canalDe(m) == _canal).toList();
    final hayAnteriores = widget.sala.anteriores[_canal] == true;
    final ultimoId = mensajes.isEmpty ? 0 : (mensajes.last['id'] as num?)?.toInt() ?? 0;
    if (ultimoId != _vistos) {
      _vistos = ultimoId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_desplazamiento.hasClients) _desplazamiento.jumpTo(_desplazamiento.position.maxScrollExtent);
      });
    }
    return Column(children: [
      if (widget.sala.bienvenida != null)
        MaterialBanner(
          content: Text(widget.sala.bienvenida!, style: const TextStyle(fontSize: 12)),
          backgroundColor: const Color(0xFFE0F2FE),
          actions: [TextButton(onPressed: () => setState(() => widget.sala.bienvenida = null), child: const Text('Entendido'))],
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: SegmentedButton<String>(
          segments: [
            const ButtonSegment(value: 'equipo', label: Text('👥 Equipo')),
            ButtonSegment(value: 'ia', label: Text(widget.sala.estadoIA['ocupada'] == true ? '🤖 IA…' : '🤖 IA del equipo')),
          ],
          selected: {_canal},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _canal = s.first),
        ),
      ),
      Expanded(
        child: mensajes.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    deIA
                        ? 'La IA es un integrante más del equipo: todos ven lo que le piden y lo que responde. Sus cambios llegan como propuesta.'
                        : 'Chat entre los integrantes de la sala. La IA no interviene aquí; para pedirle algo usa "🤖 IA del equipo" o escribe @IA.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.builder(
                controller: _desplazamiento,
                padding: const EdgeInsets.all(12),
                itemCount: mensajes.length + (hayAnteriores ? 1 : 0),
                itemBuilder: (_, i) {
                  if (hayAnteriores) {
                    if (i == 0) {
                      return Center(child: TextButton(onPressed: () => widget.sala.cargarAnteriores(_canal), child: const Text('Cargar mensajes anteriores')));
                    }
                    return _mensaje(mensajes[i - 1]);
                  }
                  return _mensaje(mensajes[i]);
                },
              ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _texto,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _mandar(),
                decoration: InputDecoration(
                  hintText: deIA ? 'Pídele algo a la IA (todo el equipo lo ve)' : 'Escribe al equipo',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            deIA
                ? IconButton.filled(onPressed: _enviando ? null : _mandar, tooltip: 'Pedir a la IA', icon: const Text('🤖'))
                : IconButton(onPressed: _enviando ? null : _mandar, tooltip: 'Enviar al equipo', icon: const Icon(Icons.send)),
          ]),
        ),
      ),
    ]);
  }
}

class VistaHistorial extends StatelessWidget {
  const VistaHistorial({super.key, required this.sala});
  final SalaEnVivo sala;

  @override
  Widget build(BuildContext context) {
    final cambios = sala.cambios.reversed.toList();
    if (cambios.isEmpty) return const Center(child: Text('Todavía no hay cambios registrados.'));
    return ListView.separated(
      itemCount: cambios.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final c = cambios[i];
        final esIA = c['esIA'] == true;
        final d = DateTime.tryParse('${c['creadoEn']}')?.toLocal();
        final cuando = d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
        return ListTile(
          dense: true,
          leading: CircleAvatar(radius: 14, backgroundColor: esIA ? const Color(0xFFEDE9FE) : const Color(0xFFDBEAFE), child: Text(esIA ? '🤖' : '${c['autorNombre'] ?? '?'}'.characters.first)),
          title: Text('${esIA ? 'IA' : c['autorNombre']} ${c['resumen']}'),
          subtitle: Text(esIA ? '$cuando · pedido por ${c['pedidoPor']}${c['aprobadoPor'] != null ? ', aprobado por ${c['aprobadoPor']}' : ''}' : cuando),
        );
      },
    );
  }
}
