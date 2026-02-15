import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:motion_photos/motion_photos.dart';
import 'package:photo_manager/photo_manager.dart';

class DiaryAssetPickerPage extends StatefulWidget {
  const DiaryAssetPickerPage({
    super.key,
    this.requestType = RequestType.image,
    this.title,
  });

  final RequestType requestType;
  final String? title;

  @override
  State<DiaryAssetPickerPage> createState() => _DiaryAssetPickerPageState();
}

class _DiaryAssetPickerPageState extends State<DiaryAssetPickerPage>
    with WidgetsBindingObserver {
  static const int _pageSize = 60;

  bool _loading = true;
  bool _hasPermission = false;
  bool _loadingMore = false;
  List<AssetPathEntity> _paths = [];
  AssetPathEntity? _path;
  final List<AssetEntity> _assets = [];
  int _page = 0;
  final ScrollController _controller = ScrollController();
  
  // 缩略图缓存，避免重复加载
  final Map<String, Uint8List> _thumbnailCache = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.addListener(_onScroll);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _thumbnailCache.clear(); // 清理缓存
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _init();
    }
  }

  void _onScroll() {
    if (_loading || _loadingMore) return;
    if (!_controller.hasClients) return;
    final position = _controller.position;
    if (position.extentAfter < 600) {
      _loadMore();
    }
  }

  Future<void> _init() async {
    if (kIsWeb) {
      setState(() {
        _loading = false;
        _hasPermission = false;
      });
      return;
    }
    final permission = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    final ok = permission.hasAccess;
    setState(() {
      _hasPermission = ok;
      _loading = false;
    });
    if (!ok) return;
    await _loadFirst();
  }

  Future<void> _reload() async {
    if (_loading) return;
    setState(() {
      _loading = true;
    });
    try {
      await PhotoManager.clearFileCache();
    } catch (_) {}
    await _loadFirst();
    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _loadFirst() async {
    final optionGroup = FilterOptionGroup(
      orders: [
        const OrderOption(type: OrderOptionType.createDate, asc: false),
      ],
    );
    var paths = await PhotoManager.getAssetPathList(
      type: widget.requestType,
      filterOption: optionGroup,
      onlyAll: false,
    );
    if (!mounted) return;
    if (paths.isEmpty) {
      paths = await PhotoManager.getAssetPathList(
        type: widget.requestType,
        filterOption: optionGroup,
        onlyAll: true,
      );
      if (!mounted) return;
    }
    if (paths.isEmpty) {
      setState(() {
        _paths = [];
        _path = null;
        _assets.clear();
        _page = 0;
        _loadingMore = false;
      });
      return;
    }
    setState(() {
      _paths = paths;
      _path = paths.where((p) => p.isAll).isNotEmpty
          ? paths.firstWhere((p) => p.isAll)
          : paths.first;
      _assets.clear();
      _thumbnailCache.clear(); // 清理旧缓存
      _page = 0;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    final path = _path;
    if (path == null) return;
    setState(() {
      _loadingMore = true;
    });
    final list = await path.getAssetListPaged(page: _page, size: _pageSize);
    if (!mounted) return;
    setState(() {
      _assets.addAll(list);
      _page += 1;
      _loadingMore = false;
    });
  }

  Future<void> _pickAlbum() async {
    final paths = _paths;
    if (paths.isEmpty) return;
    final selected = _path;
    final picked = await showModalBottomSheet<AssetPathEntity?>(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final primary = isDark ? Colors.white : Colors.black;
        final secondary =
            isDark ? Colors.white.withAlpha(160) : Colors.black.withAlpha(140);
        return SafeArea(
          top: false,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: paths.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final p = paths[index];
              final isSelected = selected?.id == p.id;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.of(context).pop(p),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withAlpha(isSelected ? 40 : 12),
                      ),
                      color: isSelected
                          ? (isDark
                              ? Colors.white.withAlpha(10)
                              : Colors.black.withAlpha(6))
                          : Colors.transparent,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          p.isAll ? Icons.photo_library_outlined : Icons.folder,
                          color: isSelected ? primary : secondary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isSelected ? primary : secondary,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(
                            Icons.check,
                            color: primary,
                            size: 18,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
    if (!mounted) return;
    if (picked == null) return;
    if (_path?.id == picked.id) return;
    setState(() {
      _path = picked;
      _assets.clear();
      _thumbnailCache.clear(); // 切换相册时清理缓存
      _page = 0;
    });
    await _loadMore();
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _probeMotion(AssetEntity entity) async {
    final file = await entity.originFile;
    if (!mounted) return;
    if (file == null) {
      _showMessage('读取原图失败');
      return;
    }
    try {
      final motionPhotos = MotionPhotos(file.path);
      final ok = await motionPhotos.isMotionPhoto();
      if (!mounted) return;
      _showMessage(ok ? '检测：这是实况照片' : '检测：不是实况照片');
    } catch (_) {
      if (!mounted) return;
      _showMessage('检测失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).textTheme.titleMedium?.color ??
        (isDark ? Colors.white : Colors.black);
    final titleText = widget.title ?? _path?.name ?? '选择照片';
    final canPickAlbum = _paths.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: canPickAlbum ? _pickAlbum : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (canPickAlbum) ...[
                const SizedBox(width: 6),
                const Icon(Icons.expand_more),
              ],
            ],
          ),
        ),
        actions: [
          IconButton(
            onPressed: _hasPermission ? _reload : null,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasPermission
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          kIsWeb ? 'Web 不支持读取相册' : '需要相册权限',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: kIsWeb ? null : PhotoManager.openSetting,
                            child: Text('去设置'),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : _assets.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.requestType == RequestType.video
                                  ? '没有读取到视频'
                                  : '没有读取到照片',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: primary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              widget.requestType == RequestType.video
                                  ? '可能原因：相册里没有视频 / 只允许访问选中的视频 / 模拟器未导入视频'
                                  : '可能原因：相册里没有照片 / 只允许访问选中的照片 / 模拟器未导入图片',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: primary.withAlpha(160),
                                height: 1.35,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _reload,
                                child: Text(
                                  widget.requestType == RequestType.video
                                      ? '刷新（查找刚拍的视频）'
                                      : '刷新（查找刚拍的照片）',
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: PhotoManager.openSetting,
                                child: Text('去设置检查权限'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed:
                                    _paths.isEmpty ? null : () => _pickAlbum(),
                                child: const Text('切换相册'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : GridView.builder(
                      controller: _controller,
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemCount: _assets.length,
                      itemBuilder: (context, index) {
                        final entity = _assets[index];
                        final cacheKey = entity.id;
                        
                        return GestureDetector(
                          onTap: () => Navigator.of(context).pop(entity),
                          onLongPress: () => _probeMotion(entity),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // 使用缓存优化缩略图加载
                                _thumbnailCache.containsKey(cacheKey)
                                    ? Image.memory(
                                        _thumbnailCache[cacheKey]!,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      )
                                    : FutureBuilder<Uint8List?>(
                                        future: entity.thumbnailDataWithSize(
                                          const ThumbnailSize(300, 300),
                                        ),
                                        builder: (context, snapshot) {
                                          final bytes = snapshot.data;
                                          if (bytes == null) {
                                            return Container(
                                              color: Colors.black.withAlpha(10),
                                            );
                                          }
                                          // 缓存缩略图
                                          _thumbnailCache[cacheKey] = bytes;
                                          return Image.memory(
                                            bytes,
                                            fit: BoxFit.cover,
                                            gaplessPlayback: true,
                                          );
                                        },
                                      ),
                                Positioned(
                                  right: 6,
                                  top: 6,
                                  child: widget.requestType ==
                                              RequestType.image &&
                                          entity.isLivePhoto
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.black.withAlpha(110),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          child: const Text(
                                            'LIVE',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                                if (widget.requestType == RequestType.video)
                                  Positioned(
                                    left: 6,
                                    bottom: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withAlpha(110),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _formatDuration(entity.duration),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0:00';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
