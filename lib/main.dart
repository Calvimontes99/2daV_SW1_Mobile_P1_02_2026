import 'package:flutter/material.dart';

import 'api.dart';
import 'notificaciones.dart';
import 'pantalla_sala.dart';
import 'push.dart';

/// Navegador de la app: lo usan los avisos para abrir la sala al tocarlos.
final navegador = GlobalKey<NavigatorState>();

Future<void> _abrirSala(int salaId, String titulo) async {
  final sesion = await Sesion.leer();
  if (sesion == null) return;
  navegador.currentState?.push(MaterialPageRoute(builder: (_) => PantallaSala(sesion: sesion, salaId: salaId, titulo: titulo)));
}

/// Diagramador móvil: versión informativa para quien está de viaje. Muestra el diagrama de la
/// sala actualizándose en vivo, el chat del equipo con la IA y quién hizo cada cambio, y avisa
/// con notificaciones cuando hay novedades.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Notificaciones.instancia.alTocar = _abrirSala;
  Push.instancia.alTocar = _abrirSala;
  await Notificaciones.instancia.iniciar();
  await Push.instancia.iniciar();
  final sesion = await Sesion.leer();
  if (sesion != null) Push.instancia.registrar(sesion);
  runApp(AppDiagramador(sesion: sesion));
}

class AppDiagramador extends StatelessWidget {
  const AppDiagramador({super.key, this.sesion});
  final Sesion? sesion;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Diagramador UML',
      navigatorKey: navegador,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF7C3AED), useMaterial3: true),
      home: sesion == null ? const PantallaInicio() : PantallaSalas(sesion: sesion!),
    );
  }
}

class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});
  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  final _servidor = TextEditingController();
  final _email = TextEditingController();
  final _clave = TextEditingController();
  bool _cargando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Sesion.ultimoServidor().then((s) => _servidor.text = s);
  }

  Future<void> _entrar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final sesion = await Api.iniciarSesion(_servidor.text, _email.text, _clave.text);
      Push.instancia.registrar(sesion);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PantallaSalas(sesion: sesion)));
    } on ErrorApi catch (e) {
      setState(() => _error = e.estado == 400 || e.estado == 401 ? 'Correo o contraseña incorrectos.' : e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 24),
            const Icon(Icons.account_tree_outlined, size: 64, color: Color(0xFF7C3AED)),
            const SizedBox(height: 12),
            Text('Diagramador UML', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Sigue el diagrama de tu equipo y a la IA desde donde estés.', textAlign: TextAlign.center),
            const SizedBox(height: 28),
            TextField(controller: _servidor, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Servidor', helperText: 'Ej.: https://diagramador-uml.onrender.com', border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Correo', border: OutlineInputBorder())),
            const SizedBox(height: 14),
            TextField(controller: _clave, obscureText: true, onSubmitted: (_) => _entrar(), decoration: const InputDecoration(labelText: 'Contraseña', border: OutlineInputBorder())),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            const SizedBox(height: 20),
            FilledButton(onPressed: _cargando ? null : _entrar, child: Padding(padding: const EdgeInsets.all(12), child: Text(_cargando ? 'Entrando…' : 'Entrar'))),
          ],
        ),
      ),
    );
  }
}

class PantallaSalas extends StatefulWidget {
  const PantallaSalas({super.key, required this.sesion});
  final Sesion sesion;
  @override
  State<PantallaSalas> createState() => _PantallaSalasState();
}

class _PantallaSalasState extends State<PantallaSalas> {
  late Future<List<Map<String, dynamic>>> _salas;

  @override
  void initState() {
    super.initState();
    _salas = Api(widget.sesion).salas();
  }

  Future<void> _recargar() async {
    setState(() => _salas = Api(widget.sesion).salas());
    await _salas;
  }

  String _hace(String? iso) {
    if (iso == null) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    final m = DateTime.now().difference(d).inMinutes;
    if (m < 1) return 'ahora';
    if (m < 60) return 'hace $m min';
    if (m < 60 * 24) return 'hace ${m ~/ 60} h';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  Future<void> _salir() async {
    await Push.instancia.olvidar(widget.sesion);
    await Sesion.cerrar();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const PantallaInicio()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis salas'),
        actions: [IconButton(onPressed: _salir, tooltip: 'Cerrar sesión', icon: const Icon(Icons.logout))],
      ),
      body: RefreshIndicator(
        onRefresh: _recargar,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _salas,
          builder: (context, s) {
            if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
            if (s.hasError) {
              final expirada = s.error is ErrorApi && ((s.error as ErrorApi).estado == 401 || (s.error as ErrorApi).estado == 403);
              return ListView(padding: const EdgeInsets.all(24), children: [
                Text(s.error is ErrorApi ? (s.error as ErrorApi).mensaje : 'No se pudieron cargar tus salas. Revisa la conexión.'),
                const SizedBox(height: 12),
                FilledButton(onPressed: expirada ? _salir : _recargar, child: Text(expirada ? 'Iniciar sesión de nuevo' : 'Reintentar')),
              ]);
            }
            final salas = s.data ?? [];
            if (salas.isEmpty) {
              return ListView(padding: const EdgeInsets.all(24), children: const [Text('Todavía no tienes salas. Créalas desde la web y aparecerán aquí.')]);
            }
            return ListView.separated(
              itemCount: salas.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final sala = salas[i];
                final pendientes = (sala['propuestasPendientes'] as num?)?.toInt() ?? 0;
                return ListTile(
                  leading: CircleAvatar(child: Text('${sala['titulo']}'.characters.first.toUpperCase())),
                  title: Text('${sala['titulo']}'),
                  subtitle: Text('${sala['propia'] == true ? 'Tuya' : 'De ${sala['dueno']}'} · ${_hace(sala['ultimaActividad'] as String?)}'),
                  trailing: pendientes > 0 ? Chip(label: Text('🤖 $pendientes'), visualDensity: VisualDensity.compact) : const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaSala(sesion: widget.sesion, salaId: (sala['id'] as num).toInt(), titulo: '${sala['titulo']}')));
                    _recargar();
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}
