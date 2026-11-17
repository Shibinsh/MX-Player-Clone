import 'dart:async';
import 'dart:io';

/// A device discovered on the local network.
class DiscoveredDevice {
  DiscoveredDevice({required this.ip, required this.openPorts, this.hostname});

  final String ip;
  final List<int> openPorts;
  final String? hostname;

  /// Best-guess label for the kind of service the device exposes.
  String get serviceHint {
    if (openPorts.contains(445)) return 'SMB share';
    if (openPorts.contains(21)) return 'FTP server';
    if (openPorts.contains(139)) return 'Windows / Samba';
    if (openPorts.contains(80) || openPorts.contains(8080)) return 'Web / media';
    return 'Reachable host';
  }
}

/// Discovers reachable hosts on the current WiFi subnet using a TCP connect
/// sweep across common file-sharing ports. Pure Dart sockets, no native code.
class NetworkScanService {
  static const List<int> commonPorts = [445, 139, 21, 80, 8080];

  /// Returns the device's own IPv4 address on a WiFi/LAN interface.
  Future<String?> localIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback && addr.address.startsWith(RegExp(r'10\.|172\.|192\.'))) {
            return addr.address;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Streams discovered devices as the /24 subnet is swept. Uses a bounded
  /// worker pool so only [concurrency] hosts are probed at a time — this keeps
  /// memory and file-descriptor pressure low and avoids freezing the UI.
  Stream<DiscoveredDevice> scan({
    Duration timeout = const Duration(milliseconds: 300),
    int concurrency = 24,
  }) async* {
    final ip = await localIp();
    if (ip == null) return;
    final prefix = ip.substring(0, ip.lastIndexOf('.'));

    final targets = <String>[
      for (var host = 1; host < 255; host++)
        if ('$prefix.$host' != ip) '$prefix.$host',
    ];

    final controller = StreamController<DiscoveredDevice>();
    var nextIndex = 0;

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;
        if (index >= targets.length || controller.isClosed) return;
        final device = await _probe(targets[index], timeout);
        if (device != null && !controller.isClosed) controller.add(device);
      }
    }

    unawaited(
      Future.wait(List.generate(concurrency, (_) => worker())).then((_) {
        if (!controller.isClosed) controller.close();
      }),
    );

    yield* controller.stream;
  }

  Future<DiscoveredDevice?> _probe(String ip, Duration timeout) async {
    // Probe all candidate ports for this host in parallel.
    final results = await Future.wait(
      commonPorts.map((port) async {
        try {
          final socket = await Socket.connect(ip, port, timeout: timeout);
          socket.destroy();
          return port;
        } catch (_) {
          return -1;
        }
      }),
    );
    final open = results.where((port) => port > 0).toList()..sort();
    if (open.isEmpty) return null;
    String? hostname;
    try {
      final result = await InternetAddress(ip)
          .reverse()
          .timeout(const Duration(milliseconds: 300));
      hostname = result.host;
    } catch (_) {}
    return DiscoveredDevice(ip: ip, openPorts: open, hostname: hostname);
  }
}
