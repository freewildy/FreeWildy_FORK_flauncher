/* FLauncher Locked - GPL-3.0-or-later */

import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/usage_history_panel_page.dart';
import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class UsageHistoryCard extends StatefulWidget {
  @override
  State<UsageHistoryCard> createState() => _UsageHistoryCardState();
}

class _UsageHistoryCardState extends State<UsageHistoryCard> {
  final _summary = FLauncherChannel().getUsageSummary();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: 12, bottom: 12),
        child: SizedBox(
          width: 220,
          height: 124,
          child: Card(
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            child: InkWell(
              onTap: () async {
                showDialog(
                  context: context,
                  builder: (_) => SettingsPanel(initialRoute: UsageHistoryPanelPage.routeName),
                );
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Colors.indigo.shade800, Colors.indigo.shade500]),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.insights, size: 30),
                    SizedBox(height: 4),
                    Text('Temps d’utilisation'),
                    FutureBuilder<Map<dynamic, dynamic>>(
                      future: _summary,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return Text('Chargement…', style: Theme.of(context).textTheme.caption);
                        final value = snapshot.data!;
                        final settings = context.watch<SettingsService>();
                        final parts = <String>[];
                        if (settings.showUsageUptime) parts.add('Démarrage ${_duration(value['uptimeMinutes'] as int)}');
                        if (settings.showUsageToday) parts.add('Aujourd’hui ${_duration(value['todayMinutes'] as int)}');
                        if (settings.showUsageWeek) parts.add('Semaine ${_duration(value['weekMinutes'] as int)}');
                        if (settings.showUsageMonth) parts.add('Mois ${_duration(value['monthMinutes'] as int)}');
                        return Text(
                          parts.isEmpty ? 'Appuyer pour consulter' : parts.join('  •  '),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.caption,
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  String _duration(int minutes) {
    final hours = minutes ~/ 60;
    final remainder = minutes % 60;
    return hours > 0 ? '${hours}h${remainder.toString().padLeft(2, '0')}' : '${remainder}m';
  }
}
