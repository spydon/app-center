import 'dart:async';

import 'package:packagekit/packagekit.dart';
import 'package:safe_change_notifier/safe_change_notifier.dart';
import 'package:snapd/snapd.dart';
import 'package:software/app/common/app_format.dart';
import 'package:software/app/common/packagekit/package_model.dart';
import 'package:software/app/common/snap/snap_sort.dart';
import 'package:software/app/common/snap/snap_utils.dart';
import 'package:software/services/packagekit/package_service.dart';
import 'package:software/services/snap_service.dart';

class CollectionModel extends SafeChangeNotifier {
  CollectionModel(
    this._snapService,
    this._packageService,
  );

  final SnapService _snapService;
  StreamSubscription<bool>? _snapChangesSub;
  StreamSubscription<bool>? _packagesChanged;

  final PackageService _packageService;

  Future<void> init() async {
    _snapChangesSub = _snapService.snapChangesInserted.listen((_) async {
      if (_snapService.snapChanges.isEmpty) {
        _installedSnaps.clear();
        _loadInstalledSnaps();
        snapServiceIsBusy = false;
      } else {
        snapServiceIsBusy = true;
      }
    });
    _enabledAppFormats.add(AppFormat.snap);
    _appFormat = AppFormat.snap;

    if (_packageService.isAvailable) {
      _enabledAppFormats.add(AppFormat.packageKit);
      await _packageService.getInstalledPackages(filters: _packageKitFilters);
      _installedPackages = _packageService.installedPackages;

      _packagesChanged =
          _packageService.installedPackagesChanged.listen((event) {
        notifyListeners();
      });

      notifyListeners();
    }

    await _loadInstalledSnaps();
    notifyListeners();

    if (_snapService.snapChanges.isEmpty) {
      await checkForSnapUpdates();
    } else {
      checkingForSnapUpdates = false;
    }
  }

  @override
  void dispose() {
    _snapChangesSub?.cancel();
    _packagesChanged?.cancel();
    super.dispose();
  }

  AppFormat? _appFormat;
  AppFormat? get appFormat => _appFormat;
  set appFormat(AppFormat? value) {
    if (value == null || value == _appFormat) return;
    _appFormat = value;
    notifyListeners();
  }

  final Set<AppFormat> _enabledAppFormats = {};
  Set<AppFormat> get enabledAppFormats => _enabledAppFormats;

  void setAppFormat(AppFormat value) {
    if (value == _appFormat) return;
    _appFormat = value;
    notifyListeners();
  }

  // SNAPS

  final Map<Snap, bool> _installedSnaps = {};
  List<Snap> get installedSnaps {
    final entryList =
        _installedSnaps.entries.toList().where((e) => e.value == false);

    final list = entryList.map((e) => e.key).toList();

    sortSnaps(snapSort: snapSort, snaps: list);

    return searchQuery == null || searchQuery?.isEmpty == true
        ? list
        : list.where((snap) => snap.name.contains(searchQuery!)).toList();
  }

  List<Snap> get installedSnapsWithUpdates {
    final entryList = _installedSnaps.entries.toList().where((e) => e.value);
    return entryList.map((e) => e.key).toList();
  }

  bool get snapUpdatesAvailable =>
      _installedSnaps.entries.where((e) => e.value == true).toList().isNotEmpty;

  bool? _snapServiceIsBusy;
  bool? get snapServiceIsBusy => _snapServiceIsBusy;
  set snapServiceIsBusy(bool? value) {
    if (value == null || value == _snapServiceIsBusy) return;
    _snapServiceIsBusy = value;
    notifyListeners();
  }

  List<Snap> get _snapsWithUpdates => _installedSnaps.entries
      .where((e) => e.value == true)
      .map((e) => e.key)
      .toList();

  Future<void> _loadInstalledSnaps() async {
    await _snapService.loadLocalSnaps();
    for (var snap in _snapService.localSnaps) {
      _installedSnaps.putIfAbsent(snap, () => false);
    }
    notifyListeners();
  }

  String? _searchQuery;
  String? get searchQuery => _searchQuery;
  void setSearchQuery(String? value) {
    if (value == _searchQuery) return;
    _searchQuery = value;
    notifyListeners();
  }

  bool? _checkingForSnapUpdates;
  bool? get checkingForSnapUpdates => _checkingForSnapUpdates;
  set checkingForSnapUpdates(bool? value) {
    if (value == null || value == _checkingForSnapUpdates) return;
    _checkingForSnapUpdates = value;
    notifyListeners();
  }

  Future<void> checkForSnapUpdates() async {
    checkingForSnapUpdates = true;
    final snapsWithUpdate = await _snapService.loadSnapsWithUpdate();
    checkingForSnapUpdates = false;
    for (var update in snapsWithUpdate) {
      for (var e in _installedSnaps.entries) {
        if (e.key.name == update.name) {
          _installedSnaps.update(e.key, (value) => true);
          notifyListeners();
        }
      }
    }
  }

  Future<void> refreshAllSnapsWithUpdates({
    required String doneMessage,
  }) async {
    await _snapService.authorize();
    if (_snapsWithUpdates.isEmpty) return;

    final firstSnap = _snapsWithUpdates.first;
    _snapService
        .refresh(
      snap: firstSnap,
      message: doneMessage,
      channel: firstSnap.channel,
      confinement: firstSnap.confinement,
    )
        .then((_) {
      notifyListeners();
      for (var snap in _snapsWithUpdates.skip(1)) {
        _snapService.refresh(
          snap: snap,
          message: doneMessage,
          confinement: snap.confinement,
          channel: snap.channel,
        );
        notifyListeners();
      }
    });
  }

  SnapSort _snapSort = SnapSort.name;
  SnapSort get snapSort => _snapSort;
  void setSnapSort(SnapSort value) {
    if (value == _snapSort) return;
    _snapSort = value;
    notifyListeners();
  }

  // PACKAGEKIT PACKAGES

  List<PackageKitPackageId>? _installedPackages;
  List<PackageKitPackageId>? get installedPackages {
    if (!_packageService.isAvailable) {
      return [];
    } else {
      if (searchQuery?.isEmpty ?? true) {
        return _installedPackages;
      }
      return _installedPackages
          ?.where((e) => e.name.contains(searchQuery!))
          .toList();
    }
  }

  bool? _loadPackagesWithUpdates;
  bool? get loadPackagesWithUpdates => _loadPackagesWithUpdates;
  void setLoadPackagesWithUpdates(bool? value) {
    if (value == null || value == _loadPackagesWithUpdates) return;
    _loadPackagesWithUpdates = value;
    notifyListeners();
  }

  final Set<PackageKitFilter> _packageKitFilters = {
    PackageKitFilter.installed,
    PackageKitFilter.gui,
    PackageKitFilter.newest,
    PackageKitFilter.application,
    PackageKitFilter.notSource,
    PackageKitFilter.notDevelopment,
  };
  Set<PackageKitFilter> get packageKitFilters => _packageKitFilters;
  Future<void> handleFilter(bool value, PackageKitFilter filter) async {
    if (!_packageService.isAvailable) return;
    if (value) {
      _packageKitFilters.add(filter);
    } else {
      _packageKitFilters.remove(filter);
    }
    await _packageService.getInstalledPackages(filters: packageKitFilters);
    notifyListeners();
  }

  Future<void> remove(PackageModel model) =>
      _packageService.remove(model: model);
}