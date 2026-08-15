import 'package:flutter/material.dart';

import '../app/streamflow_controller.dart';
import '../models/browser_entry.dart';
import 'cast_remote_sheet.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.onOpenBrowser,
    required this.onOpenFiles,
    required this.onOpenDevices,
    required this.onOpenMedia,
  });

  final StreamFlowController controller;
  final ValueChanged<Uri?> onOpenBrowser;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenDevices;
  final VoidCallback onOpenMedia;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final history = controller.history.take(3).toList(growable: false);
    final favorites = controller.favorites.take(4).toList(growable: false);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            sliver: SliverList.list(
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
                      child: Icon(Icons.play_arrow_rounded, color: colors.primary, size: 27),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'StreamFlow',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.4,
                            ),
                          ),
                          Text(
                            controller.isCasting ? 'Mit TV verbunden' : 'Bereit zum Streamen',
                            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    if (controller.isCasting)
                      IconButton.filledTonal(
                        tooltip: 'Wiedergabe steuern',
                        onPressed: () => showCastRemoteSheet(context, controller),
                        icon: const Icon(Icons.cast_connected_rounded),
                      )
                    else
                      IconButton.filledTonal(
                        tooltip: 'Geräte',
                        onPressed: onOpenDevices,
                        icon: const Icon(Icons.cast_rounded),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _SearchBar(onTap: () => onOpenBrowser(null)),
                const SizedBox(height: 20),
                _HeroCard(
                  controller: controller,
                  onOpenBrowser: () => onOpenBrowser(null),
                  onOpenDevices: onOpenDevices,
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: 'Zuletzt besucht',
                  actionLabel: history.isEmpty ? null : 'Browser öffnen',
                  onAction: history.isEmpty ? null : () => onOpenBrowser(null),
                ),
                const SizedBox(height: 10),
                if (!controller.browserLibraryLoaded)
                  const LinearProgressIndicator(minHeight: 2)
                else if (history.isEmpty)
                  _EmptyCard(
                    icon: Icons.history_rounded,
                    title: 'Noch kein Verlauf',
                    body: 'Besuchte Seiten erscheinen hier automatisch.',
                    onTap: () => onOpenBrowser(null),
                  )
                else
                  ...history.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _HistoryTile(
                        entry: entry,
                        onTap: () => onOpenBrowser(entry.url),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                const _SectionHeader(title: 'Schnellzugriff'),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1.65,
                  children: [
                    _QuickAction(
                      icon: Icons.language_rounded,
                      title: 'Browser',
                      subtitle: 'Web & Medien',
                      onTap: () => onOpenBrowser(null),
                    ),
                    _QuickAction(
                      icon: Icons.video_library_rounded,
                      title: 'Medien',
                      subtitle: '${controller.detectedMedia.length} erkannt',
                      onTap: onOpenMedia,
                    ),
                    _QuickAction(
                      icon: Icons.folder_rounded,
                      title: 'Dateien',
                      subtitle: 'Lokal übertragen',
                      onTap: onOpenFiles,
                    ),
                    _QuickAction(
                      icon: Icons.tv_rounded,
                      title: 'Geräte',
                      subtitle: controller.preferredDevice?.name ?? 'Receiver suchen',
                      onTap: onOpenDevices,
                    ),
                  ],
                ),
                if (favorites.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const _SectionHeader(title: 'Favoriten'),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 88,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: favorites.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final entry = favorites[index];
                        return _FavoriteCard(
                          entry: entry,
                          onTap: () => onOpenBrowser(entry.url),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 21, color: colors.onSurfaceVariant),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Suchen oder URL eingeben',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 20, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.controller,
    required this.onOpenBrowser,
    required this.onOpenDevices,
  });

  final StreamFlowController controller;
  final VoidCallback onOpenBrowser;
  final VoidCallback onOpenDevices;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final casting = controller.isCasting;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0.28),
            colors.surfaceContainerHigh,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  casting ? Icons.cast_connected_rounded : Icons.play_arrow_rounded,
                  color: colors.onPrimary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      casting ? 'Wird wiedergegeben' : 'Deine Medien. Dein TV.',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      casting
                          ? '${controller.activeMedia!.displayName} • ${controller.activeDevice!.name}'
                          : controller.preferredDevice == null
                              ? 'Browser öffnen, Video finden und direkt übertragen.'
                              : 'Bereit für ${controller.preferredDevice!.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: casting
                      ? () => showCastRemoteSheet(context, controller)
                      : onOpenBrowser,
                  icon: Icon(casting ? Icons.tune_rounded : Icons.language_rounded),
                  label: Text(casting ? 'Steuern' : 'Browser öffnen'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenDevices,
                  icon: const Icon(Icons.tv_rounded),
                  label: const Text('Geräte'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({this.title = '', this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        if (actionLabel != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.entry, required this.onTap});

  final BrowserEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.public_rounded, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(entry.url.host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainer,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        borderRadius: BorderRadius.circular(17),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colors.primary, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoriteCard extends StatelessWidget {
  const _FavoriteCard({required this.entry, required this.onTap});

  final BrowserEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 170,
      child: Material(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star_rounded, color: colors.primary, size: 20),
                const SizedBox(height: 8),
                Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(entry.url.host, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.title, required this.body, required this.onTap});

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, size: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(body, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
