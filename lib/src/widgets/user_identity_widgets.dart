import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../auth/auth_user.dart';
import '../design/tokens.dart';

class AuthUserAvatar extends StatelessWidget {
  const AuthUserAvatar({
    required this.user,
    super.key,
    this.radius = 28,
    this.fallbackLabel,
    this.showProviderBadge = true,
    this.showGlow = true,
  });

  final AuthUser? user;
  final double radius;
  final String? fallbackLabel;
  final bool showProviderBadge;
  final bool showGlow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initials = fallbackLabel ?? user?.initials ?? '1W';
    final isGoogle = user?.isGoogleProvider ?? false;
    final ringColors = isGoogle
        ? const [
            Color(0xFF4285F4),
            Color(0xFF34A853),
            Color(0xFFFBBC05),
            Color(0xFFEA4335),
          ]
        : [scheme.primary, scheme.tertiary];

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(colors: ringColors),
            boxShadow: showGlow
                ? [
                    BoxShadow(
                      color: (isGoogle ? ringColors.first : scheme.primary)
                          .withAlpha(55),
                      blurRadius: radius * 0.45,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.surface,
            ),
            child: ClipOval(
              child: _AvatarContent(
                user: user,
                initials: initials,
                fallbackBackground: scheme.primaryContainer,
                fallbackForeground: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AuthProviderChip extends StatelessWidget {
  const AuthProviderChip({required this.user, super.key, this.compact = false});

  final AuthUser? user;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isGoogle = user?.isGoogleProvider ?? false;
    final iconColor = isGoogle ? const Color(0xFF4285F4) : scheme.primary;
    final bgColor = isGoogle
        ? const Color(0xFF4285F4).withAlpha(22)
        : scheme.primaryContainer.withAlpha(130);
    final borderColor = isGoogle
        ? const Color(0xFF4285F4).withAlpha(70)
        : scheme.primary.withAlpha(55);
    final label = user == null
        ? 'Local session'
        : isGoogle
        ? 'Google connected'
        : user!.providerLabel;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isGoogle)
            const _GoogleGlyph(size: 14)
          else
            Icon(Icons.verified_user_outlined, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthPhotoStatusChip extends StatelessWidget {
  const AuthPhotoStatusChip({
    required this.user,
    super.key,
    this.compact = false,
  });

  final AuthUser? user;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isGoogle = user?.isGoogleProvider ?? false;
    final hasPhoto = user?.photoUrl?.trim().isNotEmpty ?? false;
    final backgroundColor = isGoogle
        ? const Color(0xFF34A853).withAlpha(20)
        : scheme.secondaryContainer.withAlpha(170);
    final borderColor = isGoogle
        ? const Color(0xFF34A853).withAlpha(80)
        : scheme.secondary.withAlpha(55);
    final label = switch ((user != null, hasPhoto, isGoogle)) {
      (false, _, _) => 'Local avatar',
      (true, true, true) => 'Google photo synced',
      (true, true, false) => 'Profile photo linked',
      (true, false, true) => 'Google avatar fallback',
      _ => 'Avatar fallback',
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isGoogle)
            const _GoogleGlyph(size: 14)
          else
            Icon(
              hasPhoto ? Icons.photo_camera_front_outlined : Icons.face_rounded,
              size: 14,
              color: scheme.secondary,
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthUserActionButton extends StatelessWidget {
  const AuthUserActionButton({
    required this.user,
    required this.onPressed,
    super.key,
    this.tooltip,
    this.radius = 17,
  });

  final AuthUser? user;
  final VoidCallback onPressed;
  final String? tooltip;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget button = Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: AuthUserAvatar(
            user: user,
            radius: radius,
            fallbackLabel: user?.initials ?? '1W',
            showGlow: false,
          ),
        ),
      ),
    );

    button = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant.withAlpha(170)),
        color: scheme.surfaceContainerLow,
      ),
      child: button,
    );

    final effectiveTooltip = tooltip;
    if (effectiveTooltip != null && effectiveTooltip.isNotEmpty) {
      button = Tooltip(message: effectiveTooltip, child: button);
    }
    return button;
  }
}

class _AvatarContent extends StatelessWidget {
  const _AvatarContent({
    required this.user,
    required this.initials,
    required this.fallbackBackground,
    required this.fallbackForeground,
  });

  final AuthUser? user;
  final String initials;
  final Color fallbackBackground;
  final Color fallbackForeground;

  @override
  Widget build(BuildContext context) {
    final photoUrl = user?.photoUrl;
    if (photoUrl != null && photoUrl.trim().isNotEmpty) {
      return Image.network(
        photoUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _FallbackAvatarFace(
          initials: initials,
          background: fallbackBackground,
          foreground: fallbackForeground,
        ),
      );
    }
    return _FallbackAvatarFace(
      initials: initials,
      background: fallbackBackground,
      foreground: fallbackForeground,
    );
  }
}

class _FallbackAvatarFace extends StatelessWidget {
  const _FallbackAvatarFace({
    required this.initials,
    required this.background,
    required this.foreground,
  });

  final String initials;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: background,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: foreground,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

class _GoogleGlyph extends StatelessWidget {
  const _GoogleGlyph({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _GoogleGlyphPainter());
  }
}

class _GoogleGlyphPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = math.max(1.6, size.width * 0.18);
    final radius = (size.width - stroke) / 2;
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: radius,
    );

    final paints = [
      Paint()
        ..color = const Color(0xFFEA4335)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
      Paint()
        ..color = const Color(0xFFFBBC05)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
      Paint()
        ..color = const Color(0xFF34A853)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
      Paint()
        ..color = const Color(0xFF4285F4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    ];

    canvas.drawArc(rect, -0.15, 0.95, false, paints[0]);
    canvas.drawArc(rect, 0.80, 0.82, false, paints[1]);
    canvas.drawArc(rect, 1.64, 1.18, false, paints[2]);
    canvas.drawArc(rect, 2.82, 2.75, false, paints[3]);

    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    final midY = size.height * 0.53;
    canvas.drawLine(
      Offset(size.width * 0.55, midY),
      Offset(size.width * 0.90, midY),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
