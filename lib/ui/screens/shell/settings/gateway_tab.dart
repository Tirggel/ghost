import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:easy_localization/easy_localization.dart';

import '../../../../core/constants.dart';
import '../../../../core/gateway.dart';
import '../../../../providers/gateway_provider.dart';
import '../../../../providers/usage_provider.dart';
import '../../../../core/internal_gateway.dart';
import '../../../widgets/app_styles.dart';
import '../../../widgets/app_dialogs.dart';

// ---------------------------------------------------------------------------
// GatewayTab — Gateway Status, Logs & Control
// ---------------------------------------------------------------------------

class GatewayTab extends ConsumerStatefulWidget {

  const GatewayTab({super.key, this.onBack, this.onNext});
  final VoidCallback? onBack;
  final VoidCallback? onNext;

  @override
  ConsumerState<GatewayTab> createState() => _GatewayTabState();
}

class _GatewayTabState extends ConsumerState<GatewayTab> {
  Map<String, dynamic>? _status;
  List<String> _methods = [];
  bool _loadingStatus = false;
  bool _loadingMethods = false;
  bool _restarting = false;

  final ScrollController _logScrollCtrl = ScrollController();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _fetchAll();

    // Auto-refresh status every 5 s
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _fetchStatus();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _logScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    await Future.wait([_fetchStatus(), _fetchMethods()]);
  }

  Future<void> _fetchStatus() async {
    if (!mounted) return;
    setState(() => _loadingStatus = true);
    try {
      final result = await ref
          .read(gatewayClientProvider)
          .call('gateway.status');
      if (mounted) setState(() => _status = result as Map<String, dynamic>?);
    } catch (_) {}
    if (mounted) setState(() => _loadingStatus = false);
  }

  Future<void> _fetchMethods() async {
    if (!mounted) return;
    setState(() => _loadingMethods = true);
    try {
      final result = await ref
          .read(gatewayClientProvider)
          .call('gateway.methods');
      if (mounted) {
        final raw = result['methods'] as List<dynamic>?;
        setState(() => _methods = raw?.map((e) => e.toString()).toList() ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingMethods = false);
  }

  Future<void> _restart() async {
    final confirmed = await AppAlertDialog.showConfirmation(
      context: context,
      title: 'settings.gateway.restart_title'.tr(),
      content: 'settings.gateway.restart_content'.tr(),
      confirmLabel: 'settings.gateway.restart_confirm'.tr(),
      isDestructive: false,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _restarting = true);
    final client = ref.read(gatewayClientProvider);
    client.setRestoring();
    try {
      await client.call('gateway.restart');
    } catch (e) {
      if (mounted) {
        showAppErrorDialog(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _restarting = false);
      // Give the server time to come back and the app to auto-reconnect
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted) unawaited(_fetchStatus());
    }
  }

  void _scrollLogsToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollCtrl.hasClients) {
        _logScrollCtrl.animateTo(
          _logScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Watch shared logs
    final logs = ref.watch(gatewayLogsProvider);

    // Auto-scroll on new entries
    ref.listen(gatewayLogsProvider, (prev, next) {
      if (next.length != (prev?.length ?? 0)) {
        _scrollLogsToBottom();
      }
    });

    return AppSettingsPage(
      onBack: widget.onBack,
      onNext: widget.onNext,
      children: [
        // ── Integrated Mode (INTERNAL HOST) ──────────────────────────
        _buildIntegratedModeSection(),
        const SizedBox(height: 32),

        // ── Status ────────────────────────────────────────────────────
        _buildStatusSection(),
        const SizedBox(height: 32),

        // ── Live Log ─────────────────────────────────────────────────
        _buildLogSection(logs),
        const SizedBox(height: 32),

        // ── Registered Methods ────────────────────────────────────────
        _buildMethodsSection(),
        const SizedBox(height: 32),
      ],
    );
  }

  // ─── Integrated Mode ─────────────────────────────────────────────────────

  Widget _buildIntegratedModeSection() {
    final gatewayManager = InternalGatewayManager();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppSectionHeader('settings.gateway.integrated_mode', large: true),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border, width: 0.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'settings.gateway.host_internal_title'.tr(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'settings.gateway.host_internal_subtitle'.tr(),
                          style: const TextStyle(
                            color: AppColors.textDim,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: gatewayManager.isRunning,
                    onChanged: (val) async {
                      await gatewayManager.setEnabled(val);
                      if (mounted) setState(() {});
                      // Trigger a refresh of the gateway URL and connection
                      ref.invalidate(gatewayUrlProvider);
                    },
                    activeThumbColor: AppColors.primary,
                  ),
                ],
              ),
              if (gatewayManager.isRunning) ...[
                const Divider(color: AppColors.border, height: 24),
                Row(
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Running on port: ${gatewayManager.port ?? '...'}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ─── Status ───────────────────────────────────────────────────────────────

  Widget _buildStatusSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppSectionHeader('settings.gateway.status_section', large: true),
            const Spacer(),
            // Restart
            _buildRestartButton(),
          ],
        ),

        if (_status == null && !_loadingStatus)
          _buildEmptyHint('settings.gateway.status_unavailable')
        else if (_status != null)
          _buildStatusCards(_status!),
      ],
    );
  }

  Widget _buildRestartButton() {
    return ElevatedButton.icon(
      onPressed: _restarting ? null : _restart,
      icon: _restarting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.black,
              ),
            )
          : const Icon(Icons.restart_alt_rounded, size: 18),
      label: Text(
        'settings.gateway.restart'.tr().toUpperCase(),
        style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.0),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.black,
        minimumSize: const Size(0, 40),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      ),
    );
  }

  Widget _buildStatusCards(Map<String, dynamic> s) {
    final port = s['port'];
    final clients = s['clients'];
    final authMode = s['authMode'];
    final startedAt = s['startedAt'] as String?;
    final uptime = s['uptime'] as int?;

    String uptimeStr = '—';
    if (uptime != null) {
      final d = Duration(seconds: uptime);
      if (d.inHours > 0) {
        uptimeStr = '${d.inHours}h ${d.inMinutes.remainder(60)}m';
      } else if (d.inMinutes > 0) {
        uptimeStr = '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
      } else {
        uptimeStr = '${d.inSeconds}s';
      }
    }

    String startedDate = '—';
    if (startedAt != null) {
      try {
        final dt = DateTime.parse(startedAt).toLocal();
        startedDate =
            '${dt.hour.toString().padLeft(2, '0')}:'
            '${dt.minute.toString().padLeft(2, '0')}:'
            '${dt.second.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    final isRunning = s['status'] == 'running';
    final connectionStatus = ref.watch(connectionStatusProvider).value;
    final isConnected = connectionStatus == ConnectionStatus.authenticated;

    final statusColor = (isRunning && isConnected)
        ? AppColors.success
        : AppColors.error;

    final tokenUsage = ref.watch(tokenUsageProvider);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          icon: Icons.circle,
          iconColor: statusColor,
          label: 'settings.gateway.stat_status',
          value: isRunning
              ? 'settings.gateway.stat_running'.tr()
              : 'common.error'.tr(),
        ),
        _StatCard(
          icon: Icons.lan_rounded,
          label: 'settings.gateway.stat_port',
          value: port?.toString() ?? '—',
        ),
        _StatCard(
          icon: Icons.people_alt_outlined,
          label: 'settings.gateway.stat_clients',
          value: clients?.toString() ?? '—',
        ),
        _StatCard(
          icon: Icons.timer_outlined,
          label: 'settings.gateway.stat_uptime',
          value: uptimeStr,
        ),
        _StatCard(
          icon: Icons.access_time_rounded,
          label: 'settings.gateway.stat_started',
          value: startedDate,
        ),
        _StatCard(
          icon: Icons.lock_outline_rounded,
          label: 'settings.gateway.stat_auth',
          value: authMode?.toString() ?? '—',
        ),
        _StatCard(
          icon: Icons.upload_file_rounded,
          label: 'settings.gateway.stat_input_tokens',
          value: tokenUsage.totalInputTokens.toString(),
          trailing: tokenUsage.totalInputTokens > 0
              ? IconButton(
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  onPressed: () => ref.read(tokenUsageProvider.notifier).reset(),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                )
              : null,
        ),
        _StatCard(
          icon: Icons.download_done_rounded,
          label: 'settings.gateway.stat_output_tokens',
          value: tokenUsage.totalOutputTokens.toString(),
        ),
      ],
    );
  }

  // ─── Log ──────────────────────────────────────────────────────────────────

  Widget _buildLogSection(List<GatewayLogEntry> logs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppSectionHeader('settings.gateway.log_section', large: true),
            const Spacer(),
            // Clear logs
            if (logs.isNotEmpty)
              TextButton.icon(
                onPressed: () => ref.read(gatewayLogsProvider.notifier).clear(),
                icon: const Icon(
                  Icons.delete_sweep_rounded,
                  size: 16,
                  color: AppColors.textDim,
                ),
                label: Text(
                  'common.clear'.tr().toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textDim,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
              ),
          ],
        ),

        Container(
          height: 260,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
          ),
          child: logs.isEmpty
              ? Center(
                  child: Text(
                    'settings.gateway.log_empty'.tr(),
                    style: const TextStyle(
                      color: AppColors.textDim,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                )
              : Scrollbar(
                  controller: _logScrollCtrl,
                  child: ListView.builder(
                    controller: _logScrollCtrl,
                    padding: const EdgeInsets.all(10),
                    itemCount: logs.length,
                    itemBuilder: (ctx, i) => _buildLogLine(logs[i]),
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          'settings.gateway.log_hint'.tr(),
          style: const TextStyle(color: AppColors.textDim, fontSize: 11),
        ),
      ],
    );
  }

  Widget _buildLogLine(GatewayLogEntry entry) {
    final timeStr =
        '${entry.time.hour.toString().padLeft(2, '0')}:'
        '${entry.time.minute.toString().padLeft(2, '0')}:'
        '${entry.time.second.toString().padLeft(2, '0')}';

    Color levelColor;
    switch (entry.level.toUpperCase()) {
      case 'SEVERE':
      case 'ERROR':
        levelColor = Colors.redAccent;
        break;
      case 'WARNING':
        levelColor = Colors.orangeAccent;
        break;
      case 'INFO':
        levelColor = AppColors.primary;
        break;
      default:
        levelColor = AppColors.textDim;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeStr,
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 50,
            alignment: Alignment.centerRight,
            child: Text(
              entry.level.toUpperCase(),
              style: TextStyle(
                color: levelColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                fontFamily: 'monospace',
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Methods ──────────────────────────────────────────────────────────────

  Widget _buildMethodsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const AppSectionHeader('settings.gateway.methods_section', large: true),
            const Spacer(),
            IconButton(
              onPressed: _loadingMethods ? null : _fetchMethods,
              icon: _loadingMethods
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      color: AppColors.textDim,
                      size: 20,
                    ),
              tooltip: 'common.refresh'.tr(),
            ),
          ],
        ),

        if (_loadingMethods)
          const Center(child: CircularProgressIndicator())
        else if (_methods.isEmpty)
          _buildEmptyHint('settings.gateway.methods_empty')
        else
          _buildMethodsGrid(),
      ],
    );
  }

  Widget _buildMethodsGrid() {
    // Group by prefix (e.g. "config", "agent", "skills")
    final groups = <String, List<String>>{};
    for (final m in _methods) {
      final prefix = m.contains('.') ? m.split('.').first : 'other';
      groups.putIfAbsent(prefix, () => []).add(m);
    }
    final sortedGroups = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedGroups.map((entry) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 10),
              child: Text(
                entry.key.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: entry.value.map((method) {
                return _MethodChip(method: method);
              }).toList(),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildEmptyHint(String key) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        key.tr(),
        style: const TextStyle(color: AppColors.textDim, fontSize: 12),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatCard — kleine Statuskarte
// ─────────────────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.iconColor,
    this.trailing,
  });
  final IconData icon;
  final Color? iconColor;
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 156,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, size: 16, color: iconColor ?? AppColors.textDim),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label.tr().toUpperCase(),
            style: const TextStyle(
              color: AppColors.textDim,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MethodChip — klickbares RPC-Method-Badge
// ─────────────────────────────────────────────────────────────────────────────

class _MethodChip extends StatefulWidget {
  const _MethodChip({required this.method});
  final String method;

  @override
  State<_MethodChip> createState() => _MethodChipState();
}

class _MethodChipState extends State<_MethodChip> {
  bool _hovered = false;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: widget.method));
          if (!mounted) return;
          setState(() => _copied = true);
          await Future<void>.delayed(const Duration(seconds: 1));
          if (mounted) setState(() => _copied = false);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered
                ? AppColors.primary.withValues(alpha: 0.12)
                : AppColors.surface,
            border: Border.all(
              color: _hovered ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Text(
            _copied ? '✓ copied' : widget.method,
            style: TextStyle(
              color: _copied
                  ? AppColors.primary
                  : (_hovered ? AppColors.primary : AppColors.textMain),
              fontSize: 11,
              fontFamily: 'monospace',
              fontWeight: _hovered ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}
