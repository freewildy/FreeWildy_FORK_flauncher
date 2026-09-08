/*
 * FLauncher Locked
 * Copyright (C) 2026
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LockService extends ChangeNotifier {
  static const _hashKey = 'launcher_lock_password_hash';
  static const _saltKey = 'launcher_lock_password_salt';
  static const _lockedAppsKey = 'launcher_lock_protected_apps';
  static const _recoveryKey = 'launcher_lock_recovery_hashes';
  static const _failedAttemptsKey = 'launcher_lock_failed_attempts';

  final SharedPreferences _preferences;
  DateTime? _administratorUnlockedUntil;
  late int _failedPasswordAttempts;

  LockService(this._preferences) {
    _failedPasswordAttempts = _preferences.getInt(_failedAttemptsKey) ?? 0;
  }

  bool get hasPassword => _preferences.containsKey(_hashKey) && _preferences.containsKey(_saltKey);

  bool isAppLocked(String packageName) =>
      (_preferences.getStringList(_lockedAppsKey) ?? const <String>[]).contains(packageName);

  bool get isAdministratorUnlocked {
    final unlockedUntil = _administratorUnlockedUntil;
    if (unlockedUntil == null) return false;
    if (DateTime.now().isBefore(unlockedUntil)) return true;
    _administratorUnlockedUntil = null;
    return false;
  }

  void unlockAdministrator() {
    _administratorUnlockedUntil = DateTime.now().add(Duration(hours: 4));
    notifyListeners();
  }

  void lockAdministrator() {
    _administratorUnlockedUntil = null;
    notifyListeners();
  }

  Future<void> setAppLocked(String packageName, bool locked) async {
    final applications = (_preferences.getStringList(_lockedAppsKey) ?? <String>[]).toSet();
    if (locked) {
      applications.add(packageName);
    } else {
      applications.remove(packageName);
    }
    await _preferences.setStringList(_lockedAppsKey, applications.toList()..sort());
    notifyListeners();
  }

  int get failedPasswordAttempts => _failedPasswordAttempts;

  bool get canUseRecovery => _failedPasswordAttempts >= 10;

  bool verify(String password) {
    final salt = _preferences.getString(_saltKey);
    final storedHash = _preferences.getString(_hashKey);
    if (salt == null || storedHash == null) return false;
    final valid = _hash(password, salt) == storedHash;
    if (valid) {
      _failedPasswordAttempts = 0;
    } else {
      _failedPasswordAttempts++;
    }
    _preferences.setInt(_failedAttemptsKey, _failedPasswordAttempts);
    notifyListeners();
    return valid;
  }

  Future<void> setPassword(String password, {List<String>? recoveryAnswers}) async {
    if (password.length < 4) throw ArgumentError('The password must contain at least 4 characters.');
    final random = Random.secure();
    final salt = base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256)));
    await _preferences.setString(_saltKey, salt);
    await _preferences.setString(_hashKey, _hash(password, salt));
    _failedPasswordAttempts = 0;
    await _preferences.setInt(_failedAttemptsKey, 0);
    if (recoveryAnswers != null) {
      if (recoveryAnswers.length != 4 || recoveryAnswers.any((answer) => answer.trim().isEmpty)) {
        throw ArgumentError('All four recovery answers are required.');
      }
      await _preferences.setStringList(
        _recoveryKey,
        List<String>.generate(4, (index) => _hashRecovery(index, recoveryAnswers[index], salt)),
      );
    }
    notifyListeners();
  }

  bool verifyRecoveryAnswers(List<String> answers) {
    final salt = _preferences.getString(_saltKey);
    final stored = _preferences.getStringList(_recoveryKey);
    if (salt == null || stored == null || stored.length != 4 || answers.length != 4) return false;
    var matches = 0;
    for (var index = 0; index < 4; index++) {
      if (_hashRecovery(index, answers[index], salt) == stored[index]) matches++;
    }
    return matches >= 3;
  }

  Future<void> resetPassword(String password) async {
    if (password.length < 4) throw ArgumentError('The password must contain at least 4 characters.');
    final salt = _preferences.getString(_saltKey);
    if (salt == null) throw StateError('Recovery is not configured.');
    await _preferences.setString(_hashKey, _hash(password, salt));
    _failedPasswordAttempts = 0;
    await _preferences.setInt(_failedAttemptsKey, 0);
    unlockAdministrator();
  }

  String _hash(String password, String salt) => sha256.convert(utf8.encode('$salt:$password')).toString();

  String _hashRecovery(int index, String answer, String salt) =>
      sha256.convert(utf8.encode('$salt:recovery:$index:${_normalizeRecovery(index, answer)}')).toString();

  String _normalizeRecovery(int index, String value) {
    if (index == 0) {
      final digits = value.replaceAll(RegExp(r'\D'), '');
      if (digits.length == 6 || digits.length == 8) {
        final day = digits.substring(0, 2);
        final month = digits.substring(2, 4);
        var year = digits.substring(4);
        if (year.length == 2) {
          final shortYear = int.parse(year);
          final currentShortYear = DateTime.now().year % 100;
          year = '${(shortYear <= currentShortYear ? 2000 : 1900) + shortYear}';
        }
        return '$year-$month-$day';
      }
    }
    var normalized = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    const replacements = <String, String>{
      'à': 'a', 'á': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a',
      'ç': 'c', 'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
      'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
      'ñ': 'n', 'ò': 'o', 'ó': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
      'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ý': 'y', 'ÿ': 'y',
      'š': 's', 'œ': 'oe',
    };
    replacements.forEach((accented, plain) => normalized = normalized.replaceAll(accented, plain));
    return normalized;
  }
}
