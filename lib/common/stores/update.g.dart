// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'update.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$UpdateStore on UpdateStoreBase, Store {
  Computed<bool>? _$hasUpdateComputed;

  @override
  bool get hasUpdate =>
      (_$hasUpdateComputed ??= Computed<bool>(() => super.hasUpdate,
          name: 'UpdateStoreBase.hasUpdate'))
          .value;

  late final _$currentVersionAtom =
  Atom(name: 'UpdateStoreBase.currentVersion', context: context);

  @override
  String get currentVersion {
    _$currentVersionAtom.reportRead();
    return super.currentVersion;
  }

  @override
  set currentVersion(String value) {
    _$currentVersionAtom.reportWrite(value, super.currentVersion, () {
      super.currentVersion = value;
    });
  }

  late final _$latestReleaseAtom =
  Atom(name: 'UpdateStoreBase.latestRelease', context: context);

  @override
  GithubRelease get latestRelease {
    _$latestReleaseAtom.reportRead();
    return super.latestRelease;
  }

  @override
  set latestRelease(GithubRelease value) {
    _$latestReleaseAtom.reportWrite(value, super.latestRelease, () {
      super.latestRelease = value;
    });
  }

  late final _$updatingAtom =
  Atom(name: 'UpdateStoreBase.updating', context: context);

  @override
  bool get updating {
    _$updatingAtom.reportRead();
    return super.updating;
  }

  @override
  set updating(bool value) {
    _$updatingAtom.reportWrite(value, super.updating, () {
      super.updating = value;
    });
  }

  late final _$refreshLatestReleaseAsyncAction =
  AsyncAction('UpdateStoreBase.refreshLatestRelease', context: context);

  @override
  Future<void> refreshLatestRelease() {
    return _$refreshLatestReleaseAsyncAction
        .run(() => super.refreshLatestRelease());
  }

  @override
  String toString() {
    return '''
currentVersion: ${currentVersion},
latestRelease: ${latestRelease},
updating: ${updating},
hasUpdate: ${hasUpdate}
    ''';
  }
}