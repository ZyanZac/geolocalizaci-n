import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: MapaPage()));

class UbicacionException implements Exception {
  const UbicacionException(this.mensaje);
  final String mensaje;
}

class MapaPage extends StatefulWidget {
  const MapaPage({super.key});
  @override
  State<MapaPage> createState() => _MapaPageState();
}

class _MapaPageState extends State<MapaPage> {
  static const _utxj = LatLng(20.2756, -97.9611);
  Set<Marker> _marcadores = {};
  GoogleMapController? _ctrl;
  StreamSubscription<Position>? _sub;
  Position? _pos;
  LatLng? _destino;
  String _direccion = '';
  String? _error;
  bool _centrado = false;

  double? get _metros {
    final p = _pos, d = _destino;
    if (p == null || d == null) return null;
    return Geolocator.distanceBetween(p.latitude, p.longitude, d.latitude, d.longitude);
  }

  @override
  void initState() {
    super.initState();
    _iniciar();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ctrl?.dispose();
    super.dispose();
  }

  Future<Position> _obtenerUbicacion() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const UbicacionException('Los servicios de ubicación están desactivados.');
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied) {
      throw const UbicacionException('Permiso de ubicación denegado.');
    }
    if (perm == LocationPermission.deniedForever) {
      throw const UbicacionException('Permiso denegado de forma permanente. Actívalo en Ajustes.');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _iniciar() async {
    await _sub?.cancel();
    try {
      final p = await _obtenerUbicacion();
      if (!mounted) return;
      setState(() {
        _pos = p;
        _error = null;
      });
      _centrar();
      _sub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen((n) {
        if (mounted) setState(() => _pos = n);
      }, onError: (_) {});
    } on UbicacionException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (_) {
      if (mounted) setState(() => _error = 'No fue posible obtener la ubicación.');
    }
  }

  void _centrar() {
    final p = _pos, c = _ctrl;
    if (p == null || c == null || _centrado) return;
    _centrado = true;
    c.animateCamera(CameraUpdate.newLatLngZoom(LatLng(p.latitude, p.longitude), 16));
  }

  Future<void> _onTap(LatLng punto) async {
    setState(() {
      _destino = punto;
      _direccion = 'Consultando dirección…';
      _marcadores = {
        Marker(
          markerId: const MarkerId('destino'),
          position: punto,
          infoWindow: const InfoWindow(title: 'Destino'),
        ),
      };
    });
    String texto;
    try {
      final lugares = await placemarkFromCoordinates(punto.latitude, punto.longitude);
      final m = lugares.isEmpty ? null : lugares.first;
      final partes = [m?.street, m?.subLocality].whereType<String>().where((s) => s.trim().isNotEmpty);
      texto = partes.isEmpty ? 'Dirección no disponible' : partes.join(', ');
    } catch (_) {
      texto = 'Dirección no disponible';
    }
    if (!mounted || _destino != punto) return;
    setState(() => _direccion = texto);
  }

  @override
  Widget build(BuildContext context) {
    final m = _metros;
    final p = _pos;
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(target: _utxj, zoom: 15.5),
            myLocationEnabled: p != null,
            myLocationButtonEnabled: true,
            markers: _marcadores,
            onMapCreated: (c) {
              _ctrl = c;
              _centrar();
            },
            onTap: _onTap,
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_error != null) ...[
                        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        Wrap(children: [
                          TextButton(onPressed: _iniciar, child: const Text('Reintentar')),
                          TextButton(onPressed: Geolocator.openAppSettings, child: const Text('Abrir Ajustes')),
                        ]),
                      ],
                      if (_error == null && p == null) const Text('Obteniendo ubicación…'),
                      if (p != null) Text('Tu posición: ${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}'),
                      if (p != null && _destino == null) const Text('Toca el mapa para fijar un destino.'),
                      if (m != null) Text('Distancia al destino: ${m.toStringAsFixed(0)} m'),
                      if (_destino != null) Text('Dirección: $_direccion'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}