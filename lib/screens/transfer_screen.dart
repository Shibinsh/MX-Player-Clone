import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../main.dart';
import '../services/transfer_history_service.dart';
import '../services/transfer_service.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  final TransferService _service = TransferService();
  final TransferHistoryService _historyService = TransferHistoryService();
  final TextEditingController _searchController = TextEditingController();
  final List<TransferHistoryRecord> _history = [];
  String _filter = 'all';
  bool _historyLoading = false;
  bool _hasMoreHistory = true;
  static const int _historyPageSize = 80;

  @override
  void initState() {
    super.initState();
    _service
      ..addListener(_onChanged)
      ..onHistoryChanged = _reloadHistory;
    _loadHistory(reset: true);
  }

  @override
  void dispose() {
    _service
      ..removeListener(_onChanged)
      ..onHistoryChanged = null
      ..stop();
    _searchController.dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Future<void> _reloadHistory() => _loadHistory(reset: true);

  Future<void> _loadHistory({required bool reset}) async {
    if (_historyLoading) return;
    setState(() => _historyLoading = true);
    try {
      final rows = await _historyService.page(
        query: _searchController.text.trim(),
        filter: _filter,
        limit: _historyPageSize,
        offset: reset ? 0 : _history.length,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _history.clear();
        _history.addAll(rows);
        _hasMoreHistory = rows.length == _historyPageSize;
      });
    } finally {
      if (mounted) setState(() => _historyLoading = false);
    }
  }

  Future<void> _deleteHistory(TransferHistoryRecord record) async {
    await _historyService.delete(record.id);
    await _reloadHistory();
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear transfer history?'),
        content: const Text('This removes all saved transfer records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _historyService.clear();
    await _reloadHistory();
  }

  Future<void> _exportHistory() async {
    final rows = await _historyService.page(limit: 10000);
    final buffer = StringBuffer()
      ..writeln('MX Player Clone Transfer History')
      ..writeln('Exported: ${DateTime.now().toIso8601String()}')
      ..writeln();
    for (final row in rows) {
      buffer.writeln(
        '${row.createdAt.toIso8601String()},${row.direction},${row.status},'
        '"${row.fileName}",${row.fileSize},"${row.senderDevice}",'
        '"${row.receiverDevice}",${row.remoteIp},'
        '${row.speedBytesPerSecond.toStringAsFixed(0)},'
        '${row.duration.inMilliseconds},"${row.error ?? ''}"',
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/mx_transfer_history.csv');
    await file.writeAsString(buffer.toString());
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Transfer history export'),
    );
  }

  Future<void> _openRecord(TransferHistoryRecord record) async {
    if (record.filePath.isEmpty || !await File(record.filePath).exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File is no longer available')),
      );
      return;
    }
    await SharePlus.instance
        .share(ShareParams(files: [XFile(record.filePath)]));
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _service.snapshot;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('File Transfer'),
        actions: [
          const ThemeToggleButton(),
          if (snapshot.running)
            IconButton(
              tooltip: 'Stop transfer',
              icon: const Icon(Icons.stop_circle_outlined),
              onPressed: _service.stop,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              Expanded(
                child: _BigButton(
                  label: 'SEND',
                  icon: Icons.arrow_upward,
                  color: const Color(0xFF21CE6E),
                  onPressed: _service.startSend,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _BigButton(
                  label: 'RECEIVE',
                  icon: Icons.arrow_downward,
                  color: const Color(0xFF4965F2),
                  onPressed: _service.startReceive,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _HistorySection(
            records: _history,
            filter: _filter,
            loading: _historyLoading,
            hasMore: _hasMoreHistory,
            searchController: _searchController,
            onFilterChanged: (filter) {
              setState(() => _filter = filter);
              _reloadHistory();
            },
            onSearchChanged: (_) => _reloadHistory(),
            onLoadMore: () => _loadHistory(reset: false),
            onDelete: _deleteHistory,
            onClear: _clearHistory,
            onExport: _exportHistory,
            onOpen: _openRecord,
          ),
          const SizedBox(height: 18),
          if (snapshot.error != null)
            _Notice(
              icon: Icons.error_outline,
              text: snapshot.error!,
              color: colorScheme.error,
            ),
          if (!snapshot.running)
            _Notice(
              icon: Icons.wifi_tethering,
              text:
                  'Use Send to share files, or Receive to accept files from Android or PC on the same WiFi/hotspot.',
              color: colorScheme.primary,
            )
          else ...[
            _ConnectionPanel(snapshot: snapshot),
            const SizedBox(height: 16),
            if (snapshot.files.isNotEmpty)
              _PublishedFiles(files: snapshot.files),
            if (snapshot.items.isNotEmpty) ...[
              const SizedBox(height: 16),
              _ProgressList(
                items: snapshot.items,
                onCancel: _service.cancel,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(112),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 28),
      label: Text(
        label,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _HistorySection extends StatelessWidget {
  const _HistorySection({
    required this.records,
    required this.filter,
    required this.loading,
    required this.hasMore,
    required this.searchController,
    required this.onFilterChanged,
    required this.onSearchChanged,
    required this.onLoadMore,
    required this.onDelete,
    required this.onClear,
    required this.onExport,
    required this.onOpen,
  });

  final List<TransferHistoryRecord> records;
  final String filter;
  final bool loading;
  final bool hasMore;
  final TextEditingController searchController;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onLoadMore;
  final ValueChanged<TransferHistoryRecord> onDelete;
  final VoidCallback onClear;
  final VoidCallback onExport;
  final ValueChanged<TransferHistoryRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final grouped = <String, List<TransferHistoryRecord>>{};
    for (final record in records) {
      grouped.putIfAbsent(record.remoteDevice, () => []).add(record);
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Transfer History',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: 'Export logs',
                  icon: const Icon(Icons.ios_share),
                  onPressed: records.isEmpty ? null : onExport,
                ),
                IconButton(
                  tooltip: 'Clear all',
                  icon: const Icon(Icons.delete_sweep_outlined),
                  onPressed: records.isEmpty ? null : onClear,
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search files, devices, IP address',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: onSearchChanged,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(
                    label: 'All',
                    value: 'all',
                    selected: filter,
                    onChanged: onFilterChanged),
                _FilterChip(
                    label: 'Sent',
                    value: 'sent',
                    selected: filter,
                    onChanged: onFilterChanged),
                _FilterChip(
                    label: 'Received',
                    value: 'received',
                    selected: filter,
                    onChanged: onFilterChanged),
                _FilterChip(
                    label: 'Failed',
                    value: 'failed',
                    selected: filter,
                    onChanged: onFilterChanged),
                _FilterChip(
                    label: 'Cancelled',
                    value: 'canceled',
                    selected: filter,
                    onChanged: onFilterChanged),
              ],
            ),
            const SizedBox(height: 12),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: Text(
                    loading ? 'Loading history...' : 'No transfer history yet',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              )
            else
              for (final entry in grouped.entries)
                _DeviceHistoryCard(
                  deviceName: entry.key.isEmpty ? 'Unknown device' : entry.key,
                  records: entry.value,
                  onDelete: onDelete,
                  onOpen: onOpen,
                ),
            if (hasMore)
              Center(
                child: TextButton.icon(
                  onPressed: loading ? null : onLoadMore,
                  icon: loading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more),
                  label: const Text('Load more'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onChanged(value),
    );
  }
}

class _DeviceHistoryCard extends StatelessWidget {
  const _DeviceHistoryCard({
    required this.deviceName,
    required this.records,
    required this.onDelete,
    required this.onOpen,
  });

  final String deviceName;
  final List<TransferHistoryRecord> records;
  final ValueChanged<TransferHistoryRecord> onDelete;
  final ValueChanged<TransferHistoryRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final sent = records.where((item) => item.direction == 'sent').length;
    final received =
        records.where((item) => item.direction == 'received').length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.devices_other),
        title: Text(deviceName,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('Sent $sent  |  Received $received'),
        children: [
          for (final group in _dateGroups(records).entries) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  group.key,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            for (final record in group.value)
              _HistoryTile(
                record: record,
                onDelete: onDelete,
                onOpen: onOpen,
              ),
          ],
        ],
      ),
    );
  }

  Map<String, List<TransferHistoryRecord>> _dateGroups(
    List<TransferHistoryRecord> items,
  ) {
    final format = DateFormat('MMM d, yyyy');
    final groups = <String, List<TransferHistoryRecord>>{};
    for (final item in items) {
      groups.putIfAbsent(format.format(item.createdAt), () => []).add(item);
    }
    return groups;
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.record,
    required this.onDelete,
    required this.onOpen,
  });

  final TransferHistoryRecord record;
  final ValueChanged<TransferHistoryRecord> onDelete;
  final ValueChanged<TransferHistoryRecord> onOpen;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final failed = record.status == 'failed' || record.status == 'canceled';
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        backgroundColor:
            failed ? colorScheme.errorContainer : colorScheme.primaryContainer,
        child: Icon(
          _iconFor(record),
          color: failed
              ? colorScheme.onErrorContainer
              : colorScheme.onPrimaryContainer,
        ),
      ),
      title:
          Text(record.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${record.direction.toUpperCase()} - ${record.status} - ${_formatBytes(record.fileSize)}\n'
        '${DateFormat('hh:mm a').format(record.createdAt)} - ${_formatBytes(record.speedBytesPerSecond)}/s - ${record.remoteIp}',
      ),
      isThreeLine: true,
      onTap: () => onOpen(record),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'delete') onDelete(record);
          if (value == 'retry') onOpen(record);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'retry', child: Text('Open / retry')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  IconData _iconFor(TransferHistoryRecord record) {
    if (record.status == 'failed') return Icons.error_outline;
    if (record.status == 'canceled') return Icons.cancel_outlined;
    if (record.direction == 'sent') return Icons.north_east;
    return Icons.south_west;
  }
}

class _ConnectionPanel extends StatelessWidget {
  const _ConnectionPanel({required this.snapshot});

  final TransferSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final url = snapshot.url ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  snapshot.mode == TransferMode.send
                      ? Icons.upload_file
                      : Icons.download_for_offline,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    snapshot.mode == TransferMode.send
                        ? 'Sharing files'
                        : 'Ready to receive',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: QrImageView(
                    data: url,
                    size: 190,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SelectableText(
              url,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Open this address in any browser on the same WiFi/hotspot. Android phones can scan the QR code.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _PublishedFiles extends StatelessWidget {
  const _PublishedFiles({required this.files});

  final List<PublishedFile> files;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Available files',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            for (final file in files)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(file.name),
                subtitle: Text(_formatBytes(file.sizeBytes)),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProgressList extends StatelessWidget {
  const _ProgressList({required this.items, required this.onCancel});

  final List<TransferItem> items;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfers',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            for (final item in items)
              _TransferProgress(item: item, onCancel: onCancel),
          ],
        ),
      ),
    );
  }
}

class _TransferProgress extends StatelessWidget {
  const _TransferProgress({required this.item, required this.onCancel});

  final TransferItem item;
  final ValueChanged<String> onCancel;

  @override
  Widget build(BuildContext context) {
    final running = item.status == TransferStatus.running;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (running)
                IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close),
                  onPressed: () => onCancel(item.id),
                )
              else
                Text(_statusText(item.status)),
            ],
          ),
          LinearProgressIndicator(
              value: item.totalBytes > 0 ? item.progress : null),
          const SizedBox(height: 5),
          Text(
            '${_formatBytes(item.bytes)} / ${item.totalBytes > 0 ? _formatBytes(item.totalBytes) : 'unknown'}'
            '${running ? ' - ${_formatBytes(item.speedBytesPerSecond)}/s' : ''}',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

String _statusText(TransferStatus status) {
  return switch (status) {
    TransferStatus.starting => 'Starting',
    TransferStatus.running => 'Running',
    TransferStatus.completed => 'Done',
    TransferStatus.failed => 'Failed',
    TransferStatus.canceled => 'Canceled',
  };
}

String _formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(size >= 10 || unit == 0 ? 0 : 1)} ${units[unit]}';
}
