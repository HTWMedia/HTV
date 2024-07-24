// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'iptv.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$IptvStore on IptvStoreBase, Store {
  Computed<List<Iptv>>? _$iptvListComputed;

  @override
  List<Iptv> get iptvList =>
      (_$iptvListComputed ??= Computed<List<Iptv>>(() => super.iptvList,
              name: 'IptvStoreBase.iptvList'))
          .value;
  Computed<({String current, String next})>? _$currentIptvProgrammesComputed;

  @override
  ({String current, String next}) get currentIptvProgrammes =>
      (_$currentIptvProgrammesComputed ??=
              Computed<({String current, String next})>(
                  () => super.currentIptvProgrammes,
                  name: 'IptvStoreBase.currentIptvProgrammes'))
          .value;

  late final _$iptvGroupListAtom =
      Atom(name: 'IptvStoreBase.iptvGroupList', context: context);

  @override
  List<IptvGroup> get iptvGroupList {
    _$iptvGroupListAtom.reportRead();
    return super.iptvGroupList;
  }

  @override
  set iptvGroupList(List<IptvGroup> value) {
    _$iptvGroupListAtom.reportWrite(value, super.iptvGroupList, () {
      super.iptvGroupList = value;
    });
  }

  late final _$currentIptvAtom =
      Atom(name: 'IptvStoreBase.currentIptv', context: context);

  @override
  Iptv get currentIptv {
    _$currentIptvAtom.reportRead();
    return super.currentIptv;
  }

  @override
  set currentIptv(Iptv value) {
    _$currentIptvAtom.reportWrite(value, super.currentIptv, () {
      super.currentIptv = value;
    });
  }

  late final _$iptvInfoVisibleAtom =
      Atom(name: 'IptvStoreBase.iptvInfoVisible', context: context);

  @override
  bool get iptvInfoVisible {
    _$iptvInfoVisibleAtom.reportRead();
    return super.iptvInfoVisible;
  }

  @override
  set iptvInfoVisible(bool value) {
    _$iptvInfoVisibleAtom.reportWrite(value, super.iptvInfoVisible, () {
      super.iptvInfoVisible = value;
    });
  }

  late final _$channelNoAtom =
      Atom(name: 'IptvStoreBase.channelNo', context: context);

  @override
  String get channelNo {
    _$channelNoAtom.reportRead();
    return super.channelNo;
  }

  @override
  set channelNo(String value) {
    _$channelNoAtom.reportWrite(value, super.channelNo, () {
      super.channelNo = value;
    });
  }

  late final _$epgListAtom =
      Atom(name: 'IptvStoreBase.epgList', context: context);

  @override
  List<Epg>? get epgList {
    _$epgListAtom.reportRead();
    return super.epgList;
  }

  @override
  set epgList(List<Epg>? value) {
    _$epgListAtom.reportWrite(value, super.epgList, () {
      super.epgList = value;
    });
  }

  late final _$refreshIptvListAsyncAction =
      AsyncAction('IptvStoreBase.refreshIptvList', context: context);

  @override
  Future<void> refreshIptvList() {
    return _$refreshIptvListAsyncAction.run(() => super.refreshIptvList());
  }

  late final _$refreshEpgListAsyncAction =
      AsyncAction('IptvStoreBase.refreshEpgList', context: context);

  @override
  Future<void> refreshEpgList() {
    return _$refreshEpgListAsyncAction.run(() => super.refreshEpgList());
  }

  @override
  String toString() {
    return '''
iptvGroupList: ${iptvGroupList},
currentIptv: ${currentIptv},
iptvInfoVisible: ${iptvInfoVisible},
channelNo: ${channelNo},
epgList: ${epgList},
iptvList: ${iptvList},
currentIptvProgrammes: ${currentIptvProgrammes}
    ''';
  }
}
