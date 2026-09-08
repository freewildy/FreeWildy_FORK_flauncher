/* FLauncher Locked - GPL-3.0-or-later */

import 'dart:async';
import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ApkInstallerPanelPage extends StatefulWidget {
  static const String routeName = 'apk_installer_panel';

  @override
  State<ApkInstallerPanelPage> createState() => _ApkInstallerPanelPageState();
}

class _ApkInstallerPanelPageState extends State<ApkInstallerPanelPage> {
  final _urlController = TextEditingController();
  final _channel = FLauncherChannel();
  HttpClient? _client;
  bool _downloading = false;
  double? _progress;
  String? _message;

  @override
  void dispose() {
    _client?.close(force: true);
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Install an APK', style: Theme.of(context).textTheme.headline6),
            Divider(),
            Text(
              'Enter a direct HTTPS link to a trusted APK. Smartphone applications may require a mouse and may not work on Android TV.',
            ),
            SizedBox(height: 16),
            TextField(
              controller: _urlController,
              autofocus: true,
              enabled: !_downloading,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _downloadAndInstall(),
              decoration: InputDecoration(labelText: 'Direct HTTPS APK URL'),
            ),
            SizedBox(height: 16),
            if (_downloading) LinearProgressIndicator(value: _progress),
            if (_message != null) ...[
              SizedBox(height: 12),
              Text(_message!, style: TextStyle(color: Theme.of(context).colorScheme.secondary)),
            ],
            SizedBox(height: 16),
            ElevatedButton.icon(
              icon: Icon(Icons.download_outlined),
              label: Text(_downloading ? 'Downloading…' : 'Download and install'),
              onPressed: _downloading ? null : _downloadAndInstall,
            ),
            if (_downloading)
              TextButton(
                onPressed: () => _client?.close(force: true),
                child: Text('Cancel'),
              ),
            Spacer(),
            Text(
              'Only install APKs obtained from a source you trust. This installer does not bypass Play Protect, package signatures, Play Integrity or Android compatibility checks.',
              style: Theme.of(context).textTheme.caption,
            ),
          ],
        ),
      );

  Future<void> _downloadAndInstall() async {
    final uri = Uri.tryParse(_urlController.text.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      setState(() => _message = 'A valid HTTPS URL is required.');
      return;
    }

    setState(() {
      _downloading = true;
      _progress = null;
      _message = 'Connecting…';
    });
    File? destination;
    try {
      _client = HttpClient()..connectionTimeout = Duration(seconds: 20);
      final request = await _client!.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'FLauncher-Locked/1.0');
      final response = await request.close().timeout(Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Server returned HTTP ${response.statusCode}.');
      }

      final directory = await getTemporaryDirectory();
      destination = File('${directory.path}${Platform.pathSeparator}administrator-download.apk');
      final sink = destination.openWrite();
      var received = 0;
      final total = response.contentLength;
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        if (mounted) {
          setState(() {
            _progress = total > 0 ? received / total : null;
            _message = total > 0
                ? 'Downloaded ${(received / 1048576).toStringAsFixed(1)} / ${(total / 1048576).toStringAsFixed(1)} MB'
                : 'Downloaded ${(received / 1048576).toStringAsFixed(1)} MB';
          });
        }
      }
      await sink.close();
      if (received == 0) throw FileSystemException('The downloaded file is empty.');

      final installerOpened = await _channel.installApk(destination.path);
      if (mounted) {
        setState(() => _message = installerOpened
            ? 'Android installer opened. Confirm the installation on screen.'
            : 'Allow FLauncher Locked to install unknown apps, then press Download and install again.');
      }
    } on Exception catch (error) {
      if (destination != null && await destination.exists()) await destination.delete();
      if (mounted) setState(() => _message = 'Download failed: $error');
    } finally {
      _client?.close();
      _client = null;
      if (mounted) setState(() => _downloading = false);
    }
  }
}
