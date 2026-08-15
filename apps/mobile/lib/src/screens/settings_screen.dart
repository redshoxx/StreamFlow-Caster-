import 'package:flutter/material.dart';

import '../app/streamflow_controller.dart';
import 'cast_remote_sheet.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.controller,
    required this.onOpenFiles,
    required this.onOpenDevices,
  });

  final StreamFlowController controller;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenDevices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.settings_rounded, color: colors.primary),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Einstellungen', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                  Text('StreamFlow 0.6.0', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 22),
          _SettingsCard(
            children: [
              _SettingsTile(
                icon: Icons.tv_rounded,
                title: 'Geräte & Verbindung',
                subtitle: controller.preferredDevice?.name ?? 'Receiver suchen und auswählen',
                onTap: onOpenDevices,
              ),
              _SettingsTile(
                icon: Icons.folder_rounded,
                title: 'Lokale Dateien',
                subtitle: 'Videos aus dem Gerätespeicher übertragen',
                onTap: onOpenFiles,
              ),
              if (controller.isCasting)
                _SettingsTile(
                  icon: Icons.cast_connected_rounded,
                  title: 'Aktive Wiedergabe',
                  subtitle: controller.activeDevice!.name,
                  onTap: () => showCastRemoteSheet(context, controller),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            children: const [
              _SettingsTile(
                icon: Icons.palette_outlined,
                title: 'Design',
                subtitle: 'Modern Dark • tiefes Blau',
              ),
              _SettingsTile(
                icon: Icons.security_rounded,
                title: 'Adblocker',
                subtitle: 'Im Browser standardmäßig aktiviert',
              ),
              _SettingsTile(
                icon: Icons.lock_outline_rounded,
                title: 'Privatsphäre',
                subtitle: 'Verlauf und Favoriten bleiben lokal auf dem Gerät',
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SettingsCard(
            children: const [
              _SettingsTile(
                icon: Icons.speed_rounded,
                title: 'Performance',
                subtitle: 'Release-optimiert • R8 auf Android TV',
              ),
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                title: 'Über StreamFlow',
                subtitle: 'Browser, Medienerkennung und lokales Casting',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(height: 1, indent: 58, color: colors.outlineVariant.withValues(alpha: 0.32)),
          ],
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      minTileHeight: 66,
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: colors.primary, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
