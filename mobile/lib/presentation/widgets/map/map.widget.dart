import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/advanced_media_filter.model.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/asyncvalue_extensions.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/base_bottom_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/map_bottom_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/map/map.state.dart';
import 'package:immich_mobile/presentation/widgets/map/map_utils.dart';
import 'package:immich_mobile/presentation/widgets/search/advanced_filter_sheet.widget.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/providers/search/advanced_filter.provider.dart';
import 'package:immich_mobile/utils/async_mutex.dart';
import 'package:immich_mobile/utils/debounce.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/map/map_theme_override.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class CustomSourceProperties implements SourceProperties {
  final Map<String, dynamic> data;
  final bool cluster;

  const CustomSourceProperties({required this.data, this.cluster = true});

  @override
  Map<String, dynamic> toJson() {
    return {
      "type": "geojson",
      "data": data,
      "cluster": cluster,
      "clusterRadius": 24,
      "clusterMinPoints": 3,
      "tolerance": 0.2,
    };
  }
}

class MapView extends ConsumerStatefulWidget {
  final LatLng? initialLocation;

  const MapView({super.key, this.initialLocation});

  @override
  ConsumerState<MapView> createState() => _MapViewState();
}

class _MapViewState extends ConsumerState<MapView> {
  static const String _localSourceId = 'immich-local-map-source';
  static const String _localLayerId = 'immich-local-map-layer';

  MapLibreMapController? mapController;
  final _reloadMutex = AsyncMutex();
  final _debouncer = Debouncer(interval: const Duration(milliseconds: 500), maxWaitTime: const Duration(seconds: 2));
  final ValueNotifier<double> bottomSheetOffset = ValueNotifier(0.25);
  final GlobalKey _bottomSheetKey = GlobalKey();
  StreamSubscription? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _eventSubscription = EventStream.shared.listen<MapMarkerReloadEvent>(_onEvent);
  }

  @override
  void dispose() {
    _debouncer.dispose();
    bottomSheetOffset.dispose();
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }

  void onMapCreated(MapLibreMapController controller) {
    mapController = controller;
    controller.onFeatureTapped.add(_onFeatureTapped);
  }

  Future<void> _onFeatureTapped(
    Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) async {
    final controller = mapController;
    if (controller == null || !mounted) {
      return;
    }
    final currentZoom = controller.cameraPosition?.zoom ?? 4.0;
    final targetZoom = max(currentZoom + 2.5, MapUtils.mapZoomToAssetLevel);
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(coordinates, targetZoom),
      duration: const Duration(milliseconds: 500),
    );
    _debouncer.run(() => setBounds(forceReload: true));
  }

  void _onEvent(_) => _debouncer.run(() => setBounds(forceReload: true));

  Future<void> onMapReady() async {
    final controller = mapController;
    if (controller == null) {
      return;
    }

    await controller.addSource(
      MapUtils.defaultSourceId,
      const CustomSourceProperties(data: {'type': 'FeatureCollection', 'features': []}),
    );

    await controller.addSource(
      _localSourceId,
      const CustomSourceProperties(data: {'type': 'FeatureCollection', 'features': []}),
    );

    if (Platform.isAndroid) {
      await controller.addCircleLayer(
        MapUtils.defaultSourceId,
        MapUtils.defaultHeatMapLayerId,
        const CircleLayerProperties(
          circleRadius: 11,
          circleColor: "rgba(230,92,36,0.78)",
          circleBlur: 0.4,
          circleOpacity: 0.85,
          circleStrokeWidth: 1.5,
          circleStrokeColor: "rgba(255,255,255,0.85)",
          circleStrokeOpacity: 0.9,
        ),
      );

      await controller.addCircleLayer(
        _localSourceId,
        _localLayerId,
        const CircleLayerProperties(
          circleRadius: 10,
          circleColor: "rgba(0,150,136,0.82)",
          circleBlur: 0.3,
          circleOpacity: 0.85,
          circleStrokeWidth: 1.5,
          circleStrokeColor: "rgba(255,255,255,0.9)",
          circleStrokeOpacity: 0.9,
        ),
      );
    }

    if (Platform.isIOS) {
      await controller.addHeatmapLayer(
        MapUtils.defaultSourceId,
        MapUtils.defaultHeatMapLayerId,
        MapUtils.defaultHeatmapLayerProperties,
      );
    }

    _debouncer.run(() => setBounds(forceReload: true));
    controller.addListener(onMapMoved);
  }

  void onMapMoved() {
    if (mapController!.isCameraMoving || !mounted) {
      return;
    }

    _debouncer.run(setBounds);
  }

  Future<void> setBounds({bool forceReload = false}) async {
    final controller = mapController;
    if (controller == null || !mounted) {
      return;
    }

    if (ref.read(isAssetViewerOpenProvider)) {
      return;
    }

    final bounds = await controller.getVisibleRegion();
    unawaited(
      _reloadMutex.run(() async {
        if (mounted && (ref.read(mapStateProvider.notifier).setBounds(bounds) || forceReload)) {
          final showServer = ref.read(showServerMapMarkersProvider);
          final showLocal = ref.read(showLocalMapMarkersProvider);

          final serverMarkers = showServer
              ? await ref.read(mapMarkerProvider(bounds).future)
              : const <String, dynamic>{'type': 'FeatureCollection', 'features': <dynamic>[]};
          final localMarkers = showLocal
              ? await ref.read(localMapMarkerProvider(bounds).future)
              : const <String, dynamic>{'type': 'FeatureCollection', 'features': <dynamic>[]};

          await reloadMarkers(serverMarkers, localMarkers);
        }
      }),
    );
  }

  Future<void> reloadMarkers(
    Map<String, dynamic> serverMarkers,
    Map<String, dynamic> localMarkers,
  ) async {
    final controller = mapController;
    if (controller == null || !mounted) {
      return;
    }

    await controller.setGeoJsonSource(MapUtils.defaultSourceId, serverMarkers);
    await controller.setGeoJsonSource(_localSourceId, localMarkers);
  }

  Future<void> onZoomToLocation() async {
    final (location, error) = await MapUtils.checkPermAndGetLocation(context: context);
    if (error != null) {
      if (error == LocationPermission.unableToDetermine && context.mounted) {
        ImmichToast.show(
          context: context,
          gravity: ToastGravity.BOTTOM,
          toastType: ToastType.error,
          msg: context.t.map_cannot_get_user_location,
        );
      }
      return;
    }

    final controller = mapController;
    if (controller != null && location != null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(LatLng(location.latitude, location.longitude), MapUtils.mapZoomToAssetLevel),
        duration: const Duration(milliseconds: 800),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final showServer = ref.watch(showServerMapMarkersProvider);
    final showLocal = ref.watch(showLocalMapMarkersProvider);

    ref.listen<bool>(isAssetViewerOpenProvider, (previous, current) {
      if (previous == true && !current) {
        _debouncer.run(() => setBounds(forceReload: true));
      }
    });
    return Stack(
      children: [
        _Map(initialLocation: widget.initialLocation, onMapCreated: onMapCreated, onMapReady: onMapReady),
        Positioned(
          top: context.padding.top + kToolbarHeight + 8,
          left: 12,
          right: 12,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: context.colorScheme.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilterChip(
                    avatar: const CircleAvatar(backgroundColor: Color(0xFFE65C24), radius: 6),
                    label: const Text('服务器照片', style: TextStyle(fontSize: 12)),
                    selected: showServer,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) {
                      ref.read(showServerMapMarkersProvider.notifier).state = v;
                      _debouncer.run(() => setBounds(forceReload: true));
                    },
                  ),
                  const SizedBox(width: 6),
                  FilterChip(
                    avatar: const CircleAvatar(backgroundColor: Color(0xFF009688), radius: 6),
                    label: const Text('本地照片', style: TextStyle(fontSize: 12)),
                    selected: showLocal,
                    visualDensity: VisualDensity.compact,
                    onSelected: (v) {
                      ref.read(showLocalMapMarkersProvider.notifier).state = v;
                      _debouncer.run(() => setBounds(forceReload: true));
                    },
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    avatar: const Icon(Icons.location_off_outlined, size: 15),
                    label: const Text('查看无 GPS 照片', style: TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      unawaited(
                        ref.read(advancedFilteredAssetsProvider.notifier).applyFilter(
                              const AdvancedMediaFilter(gpsFilter: TriStateFilter.no),
                            ),
                      );
                      unawaited(openAdvancedFilterBrowser(context));
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        _DynamicBottomSheet(bottomSheetOffset: bottomSheetOffset, sheetKey: _bottomSheetKey),
        _DynamicMyLocationButton(onZoomToLocation: onZoomToLocation, bottomSheetOffset: bottomSheetOffset),
      ],
    );
  }
}

class _Map extends StatelessWidget {
  final LatLng? initialLocation;

  const _Map({this.initialLocation, required this.onMapCreated, required this.onMapReady});

  final MapCreatedCallback onMapCreated;

  final VoidCallback onMapReady;

  @override
  Widget build(BuildContext context) {
    final initialLocation = this.initialLocation;
    return MapThemeOverride(
      mapBuilder: (style) => style.widgetWhen(
        onData: (style) => MapLibreMap(
          initialCameraPosition: initialLocation == null
              ? const CameraPosition(target: LatLng(0, 0), zoom: 0)
              : CameraPosition(target: initialLocation, zoom: MapUtils.mapZoomToAssetLevel),
          compassEnabled: false,
          rotateGesturesEnabled: false,
          styleString: style,
          onMapCreated: onMapCreated,
          onStyleLoadedCallback: onMapReady,
          attributionButtonPosition: AttributionButtonPosition.topRight,
          attributionButtonMargins: const Point(8, kToolbarHeight),
        ),
      ),
    );
  }
}

class _DynamicBottomSheet extends StatefulWidget {
  final ValueNotifier<double> bottomSheetOffset;
  final GlobalKey sheetKey;

  const _DynamicBottomSheet({required this.bottomSheetOffset, required this.sheetKey});

  @override
  State<_DynamicBottomSheet> createState() => _DynamicBottomSheetState();
}

class _DynamicBottomSheetState extends State<_DynamicBottomSheet> {
  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        final sheet = notification.context.findAncestorWidgetOfExactType<BaseBottomSheet>();
        if (sheet?.key == widget.sheetKey) {
          widget.bottomSheetOffset.value = notification.extent;
        }
        return false;
      },
      child: MapBottomSheet(sheetKey: widget.sheetKey),
    );
  }
}

class _DynamicMyLocationButton extends StatelessWidget {
  const _DynamicMyLocationButton({required this.onZoomToLocation, required this.bottomSheetOffset});

  final VoidCallback onZoomToLocation;
  final ValueNotifier<double> bottomSheetOffset;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: bottomSheetOffset,
      builder: (context, offset, child) {
        return Positioned(
          right: 20,
          bottom: context.height * (offset - 0.02) + context.padding.bottom,
          child: AnimatedOpacity(
            opacity: offset < 0.8 ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: ElevatedButton(
              onPressed: onZoomToLocation,
              style: ElevatedButton.styleFrom(shape: const CircleBorder()),
              child: const Icon(Icons.my_location),
            ),
          ),
        );
      },
    );
  }
}
