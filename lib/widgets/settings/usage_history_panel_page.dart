/* FLauncher Locked - GPL-3.0-or-later */

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/widgets/lock_dialog.dart';
import 'package:flutter/material.dart';

class UsageHistoryPanelPage extends StatefulWidget {
  static const String routeName = 'usage_history_panel';

  @override
  State<UsageHistoryPanelPage> createState() => _UsageHistoryPanelPageState();
}

class _UsageHistoryPanelPageState extends State<UsageHistoryPanelPage> {
  final _channel = FLauncherChannel();
  late Future<List<dynamic>> _history = _load();

  Future<List<dynamic>> _load() async {
    if (!await _channel.hasUsageAccess()) return <dynamic>[];
    return _channel.getUsageHistory(7);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Historique d’utilisation', style: Theme.of(context).textTheme.headline6)),
              TextButton.icon(
                icon: Icon(Icons.delete_outline),
                label: Text('Réinitialiser'),
                onPressed: _resetHistory,
              ),
            ],
          ),
          Divider(),
          FutureBuilder<bool>(
            future: _channel.hasUsageAccess(),
            builder: (context, permission) {
              if (permission.connectionState != ConnectionState.done) return LinearProgressIndicator();
              if (permission.data != true) {
                return Column(
                  children: [
                    Text("L’accès aux données d’utilisation Android est requis. Les statistiques restent sur cet appareil."),
                    SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () async {
                        await _channel.openUsageAccessSettings();
                      },
                      child: Text("Autoriser l’accès"),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _history = _load()),
                      child: Text('Actualiser'),
                    ),
                  ],
                );
              }
              return Expanded(
                child: FutureBuilder<List<dynamic>>(
                  future: _history,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return Center(child: CircularProgressIndicator());
                    if (snapshot.data!.isEmpty) return Center(child: Text('Aucune utilisation enregistrée ces 7 derniers jours.'));
                    return ListView.separated(
                      itemCount: snapshot.data!.length,
                      separatorBuilder: (_, __) => Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = Map<dynamic, dynamic>.from(snapshot.data![index] as Map);
                        return ListTile(
                          dense: true,
                          title: Text(entry['label'] as String),
                          subtitle: Text(entry['day'] as String),
                          trailing: Text(_duration(entry['minutes'] as int)),
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),
        ],
      );

  Future<void> _resetHistory() async {
    if (!await requestLauncherUnlock(context) || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Réinitialiser l’historique ?"),
        content: Text("Les durées enregistrées avant maintenant ne seront plus affichées. Cette action ne modifie pas l’historique Internet."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Réinitialiser')),
        ],
      ),
    );
    if (confirmed == true) {
      await _channel.resetUsageHistory();
      if (mounted) setState(() => _history = _load());
    }
  }

  String _duration(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return hours > 0 ? '${hours}h ${remainder}m' : '${remainder}m';
  }
}
