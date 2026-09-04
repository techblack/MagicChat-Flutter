import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class StoredPushInstallation {
  const StoredPushInstallation({
    required this.installationId,
    required this.managementToken,
    required this.provider,
    required this.platform,
    required this.environment,
    required this.providerToken,
    required this.appVersion,
  });

  final String installationId;
  final String managementToken;
  final String provider;
  final String platform;
  final String environment;
  final String providerToken;
  final String appVersion;

  Map<String, String> toJson() => {
        'installation_id': installationId,
        'management_token': managementToken,
        'provider': provider,
        'platform': platform,
        'environment': environment,
        'provider_token': providerToken,
        'app_version': appVersion,
      };

  factory StoredPushInstallation.fromJson(Map<String, dynamic> value) {
    final fields = [
      value['installation_id'],
      value['management_token'],
      value['provider'],
      value['platform'],
      value['environment'],
      value['provider_token'],
      value['app_version'],
    ];
    if (fields.any((field) => field is! String || field.trim().isEmpty)) {
      throw const FormatException('推送安装凭据格式不正确');
    }
    return StoredPushInstallation(
        installationId: value['installation_id'] as String,
        managementToken: value['management_token'] as String,
        provider: value['provider'] as String,
        platform: value['platform'] as String,
        environment: value['environment'] as String,
        providerToken: value['provider_token'] as String,
        appVersion: value['app_version'] as String);
  }
}

class StoredPushGrant {
  const StoredPushGrant({
    required this.grantId,
    required this.sendToken,
    required this.expiresAt,
    required this.installationId,
    required this.serverUrl,
  });

  final String grantId;
  final String sendToken;
  final DateTime expiresAt;
  final String installationId;
  final String serverUrl;

  Map<String, String> toJson() => {
        'grant_id': grantId,
        'send_token': sendToken,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'installation_id': installationId,
        'server_url': serverUrl,
      };

  factory StoredPushGrant.fromJson(Map<String, dynamic> value) {
    final expiresAt = value['expires_at'] is String
        ? DateTime.tryParse(value['expires_at'] as String)?.toUtc()
        : null;
    final fields = [
      value['grant_id'],
      value['send_token'],
      value['installation_id'],
      value['server_url']
    ];
    if (fields.any((field) => field is! String || field.trim().isEmpty) ||
        expiresAt == null) {
      throw const FormatException('推送授权格式不正确');
    }
    return StoredPushGrant(
        grantId: value['grant_id'] as String,
        sendToken: value['send_token'] as String,
        expiresAt: expiresAt,
        installationId: value['installation_id'] as String,
        serverUrl: value['server_url'] as String);
  }
}

class PushRegistrationStore {
  const PushRegistrationStore(
      {FlutterSecureStorage storage = const FlutterSecureStorage()})
      : _storage = storage;

  static const _installationKey = 'magicchat.push.installation';
  static const _grantKey = 'magicchat.push.grant';
  final FlutterSecureStorage _storage;

  Future<StoredPushInstallation?> readInstallation() async {
    final raw = await _read(_installationKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic>
          ? StoredPushInstallation.fromJson(value)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeInstallation(StoredPushInstallation value) =>
      _write(_installationKey, value.toJson());

  Future<void> clearInstallation() => _delete(_installationKey);

  Future<StoredPushGrant?> readGrant() async {
    final raw = await _read(_grantKey);
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw);
      return value is Map<String, dynamic>
          ? StoredPushGrant.fromJson(value)
          : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeGrant(StoredPushGrant value) =>
      _write(_grantKey, value.toJson());

  Future<void> clearGrant() => _delete(_grantKey);

  Future<String?> _read(String key) async {
    try {
      return await _storage.read(key: key);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> _write(String key, Map<String, String> value) async {
    try {
      await _storage.write(key: key, value: jsonEncode(value));
    } on PlatformException {
      // Secure storage is optional on unsupported desktop/CI environments.
    } on MissingPluginException {
      // Secure storage is optional on unsupported desktop/CI environments.
    }
  }

  Future<void> _delete(String key) async {
    try {
      await _storage.delete(key: key);
    } on PlatformException {
      // Secure storage is optional on unsupported desktop/CI environments.
    } on MissingPluginException {
      // Secure storage is optional on unsupported desktop/CI environments.
    }
  }
}
