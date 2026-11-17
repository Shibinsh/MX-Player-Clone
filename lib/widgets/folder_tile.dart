import 'package:flutter/material.dart';
import '../models/video_folder.dart';

class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.folder,
    required this.onTap,
    this.highlight = false,
    this.badgeText,
  });

  final VideoFolder folder;
  final VoidCallback onTap;
  final bool highlight;
  final String? badgeText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                const _FolderIcon(),
                if (badgeText != null)
                  Positioned(
                    right: -8,
                    top: -2,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF2D63),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      child: SizedBox(
                        width: 25,
                        height: 25,
                        child: Center(
                          child: Text(
                            badgeText!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    folder.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: highlight
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${folder.count} ${folder.count == 1 ? 'Video' : 'Videos'}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderIcon extends StatelessWidget {
  const _FolderIcon();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CustomPaint(
      size: const Size(68, 50),
      painter: _FolderPainter(colorScheme.surfaceContainerHighest),
    );
  }
}

class _FolderPainter extends CustomPainter {
  const _FolderPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final tabPath = Path()
      ..moveTo(0, 8)
      ..quadraticBezierTo(0, 0, 8, 0)
      ..lineTo(28, 0)
      ..quadraticBezierTo(36, 0, 42, 8)
      ..lineTo(size.width - 8, 8)
      ..quadraticBezierTo(size.width, 8, size.width, 16)
      ..lineTo(size.width, size.height - 8)
      ..quadraticBezierTo(size.width, size.height, size.width - 8, size.height)
      ..lineTo(8, size.height)
      ..quadraticBezierTo(0, size.height, 0, size.height - 8)
      ..close();
    canvas.drawPath(tabPath, paint);
  }

  @override
  bool shouldRepaint(covariant _FolderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
