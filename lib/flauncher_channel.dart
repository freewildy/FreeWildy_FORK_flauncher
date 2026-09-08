/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:async';

import 'package:flutter/services.dart';

class FLauncherChannel {
  static const _methodChannel = MethodChannel('me.efesser.flauncher/method');
  static const _eventChannel = EventChannel('me.efesser.flauncher/event');

  Future<List<dynamic>> getApplications() async => (await _methodChannel.invokeListMethod('getApplications'))!;

  Future<void> launchApp(String packageName) async => await _methodChannel.invokeMethod('launchApp', packageName);

  Future<void> openSettings() async => await _methodChannel.invokeMethod('openSettings');

  Future<void> openAppInfo(String packageName) async => await _methodChannel.invokeMethod('openAppInfo', packageName);

  Future<void> uninstallApp(String packageName) async => await _methodChannel.invokeMethod('uninstallApp', packageName);

  Future<bool> installApk(String filePath) async => await _methodChannel.invokeMethod('installApk', filePath);

  Future<bool> hasUsageAccess() async => await _methodChannel.invokeMethod('hasUsageAccess');

  Future<void> openUsageAccessSettings() async => await _methodChannel.invokeMethod('openUsageAccessSettings');

  Future<List<dynamic>> getUsageHistory(int days) async =>
      (await _methodChannel.invokeListMethod('getUsageHistory', days))!;

  Future<Map<dynamic, dynamic>> getUsageSummary() async =>
      (await _methodChannel.invokeMapMethod('getUsageSummary'))!;

  Future<bool> resetUsageHistory() async => await _methodChannel.invokeMethod('resetUsageHistory');

  Future<bool> isDefaultLauncher() async => await _methodChannel.invokeMethod('isDefaultLauncher');

  Future<bool> checkForGetContentAvailability() async =>
      await _methodChannel.invokeMethod("checkForGetContentAvailability");

  void addAppsChangedListener(void Function(Map<dynamic, dynamic>) listener) =>
      _eventChannel.receiveBroadcastStream().listen((event) => listener(event));
}
