import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/local_album.model.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/local_album_bottom_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/aves_control_bar.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/aves_floating_header_sliver.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/aves_timeline_header.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/aves_settings.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/widgets/common/mesmerizing_sliver_app_bar.dart';

@RoutePage()
class LocalTimelinePage extends ConsumerWidget {
  final LocalAlbum album;

  const LocalTimelinePage({super.key, required this.album});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avesSettings = ref.watch(avesSettingsProvider);

    return ProviderScope(
      overrides: [
        timelineServiceProvider.overrideWith((ref) {
          final timelineService = ref.watch(timelineFactoryProvider).localAlbum(albumId: album.id);
          ref.onDispose(timelineService.dispose);
          return timelineService;
        }),
      ],
      child: Timeline(
        // 本地文件夹相册：同样给一条下滑浮出的 Aves 胶囊栏
        appBar: SliverMainAxisGroup(
          slivers: [
            MesmerizingSliverAppBar(title: album.name),
            AvesFloatingHeaderSliver(
              child: AvesTimelineHeaderBottom(
                height: AvesTimelineHeaderBottom.computeHeight(avesSettings),
                browseMode: GalleryBrowseMode.localGallery,
                scope: AvesHeaderScope.localAlbum,
                albumId: album.id,
              ),
            ),
          ],
        ),
        bottomSheet: const LocalAlbumBottomSheet(),
        showStorageIndicator: true,
      ),
    );
  }
}
