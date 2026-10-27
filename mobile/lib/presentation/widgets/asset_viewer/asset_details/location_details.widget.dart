import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/presentation/actions/edit_location.action.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/sheet_tile.widget.dart';
import 'package:immich_mobile/providers/infrastructure/toast.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/asset_viewer/detail_panel/exif_map.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class LocationDetails extends ConsumerStatefulWidget {
  final BaseAsset asset;
  final ExifInfo? exifInfo;

  const LocationDetails({super.key, required this.asset, this.exifInfo});

  @override
  ConsumerState createState() => _LocationDetailsState();
}

class _LocationDetailsState extends ConsumerState<LocationDetails> {
  MapLibreMapController? _mapController;

  String? _getLocationName(ExifInfo? exifInfo) {
    if (exifInfo == null) {
      return null;
    }

    final cityName = exifInfo.city;
    final stateName = exifInfo.state;

    if (cityName != null && stateName != null) {
      return "$cityName, $stateName";
    }
    return null;
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
  }

  @override
  void didUpdateWidget(LocationDetails oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exifInfo != oldWidget.exifInfo) {
      final exif = widget.exifInfo;
      if (exif != null && exif.hasCoordinates) {
        unawaited(_mapController?.moveCamera(CameraUpdate.newLatLng(LatLng(exif.latitude!, exif.longitude!))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.asset;
    final exifInfo = widget.exifInfo;
    final double? lat = exifInfo?.latitude ?? (asset is LocalAsset ? asset.latitude : null);
    final double? lng = exifInfo?.longitude ?? (asset is LocalAsset ? asset.longitude : null);
    final hasCoordinates = lat != null && lng != null && lat != 0 && lng != 0 && !lat.isNaN && !lng.isNaN;

    // For local-only assets without GPS coordinates, hide the server location editor
    if (asset is! RemoteAsset && !hasCoordinates) {
      return const SizedBox.shrink();
    }

    final effectiveExif = exifInfo ?? (hasCoordinates ? ExifInfo(latitude: lat, longitude: lng) : null);
    final editLocation = asset is RemoteAsset ? const EditLocationAction(source: .viewer).create(context, ref) : null;
    final locationName = _getLocationName(effectiveExif);
    final coordinates = hasCoordinates ? "${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}" : "";

    void copyCoordinates() {
      if (!hasCoordinates) {
        return;
      }
      unawaited(Clipboard.setData(ClipboardData(text: coordinates)));
      unawaited(Future.value(ref.read(toastServiceProvider).success('已复制 GPS 坐标: $coordinates')));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SheetTile(
            title: context.t.location,
            titleStyle: context.textTheme.labelLarge?.copyWith(color: context.colorScheme.onSurfaceSecondary),
            trailing: hasCoordinates && editLocation != null ? const Icon(Icons.edit_location_alt, size: 20) : null,
            onTap: editLocation?.onAction,
          ),
          if (hasCoordinates && effectiveExif != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: context.isMobile ? 16.0 : 56.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExifMap(
                    exifInfo: effectiveExif,
                    markerId: asset.id,
                    markerAssetThumbhash: asset is RemoteAsset ? asset.thumbHash : null,
                    onMapCreated: _onMapCreated,
                  ),
                  const SizedBox(height: 12),
                  if (locationName != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4.0),
                      child: Text(locationName, style: context.textTheme.labelLarge),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: copyCoordinates,
                          onLongPress: copyCoordinates,
                          borderRadius: const BorderRadius.all(Radius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    coordinates,
                                    style: context.textTheme.bodySmall?.copyWith(
                                      color: context.colorScheme.onSurfaceSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.copy_rounded,
                                  size: 14,
                                  color: context.colorScheme.onSurfaceSecondary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          unawaited(context.pushRoute(MapRoute(initialLocation: LatLng(lat, lng))));
                        },
                        icon: const Icon(Icons.map_outlined, size: 16),
                        label: const Text('在地图中查看'),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (!hasCoordinates && asset is RemoteAsset)
            SheetTile(
              title: context.t.add_a_location,
              titleStyle: context.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: context.primaryColor,
              ),
              leading: const Icon(Icons.location_off),
              onTap: editLocation?.onAction,
            ),
        ],
      ),
    );
  }
}
