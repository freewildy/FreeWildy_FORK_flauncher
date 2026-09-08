/* FLauncher Locked - GPL-3.0-or-later */

import 'package:flauncher/providers/lock_service.dart';
import 'package:flauncher/widgets/lock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdministratorModeCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Consumer<LockService>(
        builder: (context, lockService, _) {
          final administrator = lockService.isAdministratorUnlocked;
          return Padding(
            padding: EdgeInsets.only(left: 24, bottom: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 220,
                height: 124,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  child: InkWell(
                    onTap: () async {
                      if (administrator) {
                        lockService.lockAdministrator();
                      } else {
                        await requestLauncherUnlock(context);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: administrator
                              ? [Colors.green.shade800, Colors.green.shade500]
                              : [Colors.blueGrey.shade800, Colors.blueGrey.shade600],
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(administrator ? Icons.admin_panel_settings : Icons.lock_outline, size: 44),
                          SizedBox(height: 8),
                          Text(administrator ? 'Mode administrateur' : 'Mode restreint'),
                          Text(
                            administrator ? 'Appuyer pour verrouiller' : 'Appuyer pour déverrouiller',
                            style: Theme.of(context).textTheme.caption,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
}
