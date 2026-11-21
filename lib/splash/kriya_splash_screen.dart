import 'package:flutter/material.dart';

class KriyaSplashScreen extends StatefulWidget {
  final Future<void> Function() onBootstrap;
  final Widget Function(BuildContext) builder;
  final Widget Function(BuildContext, String)? onErrorBuilder;

  const KriyaSplashScreen({
    super.key,
    required this.onBootstrap,
    required this.builder,
    this.onErrorBuilder,
  });

  @override
  State<KriyaSplashScreen> createState() => _KriyaSplashScreenState();
}

class _KriyaSplashScreenState extends State<KriyaSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _pulseAnimation;
  late final Animation<double> _fadeAnimation;

  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _scaleAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _pulseAnimation = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeInOutSine),
      ),
    );

    _animController.repeat(reverse: true);
    _startInitialization();
  }

  Future<void> _startInitialization() async {
    final stopwatch = Stopwatch()..start();
    try {
      await widget.onBootstrap();
      final elapsed = stopwatch.elapsedMilliseconds;
      // Guarantee at least 800ms of smooth animation display so it doesn't flicker
      if (elapsed < 800) {
        await Future.delayed(Duration(milliseconds: 800 - elapsed));
      }
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.onErrorBuilder != null) {
        return widget.onErrorBuilder!(context, _error!);
      }
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: const Color(0xFF0B0F17),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Initialization error:\n$_error',
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
              ),
            ),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: _isInitialized
          ? widget.builder(context)
          : _buildSplashContent(context),
    );
  }

  Widget _buildSplashContent(BuildContext context) {
    return MaterialApp(
      key: const ValueKey('splash_view'),
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: const Color(0xFF070A0F),
        body: Stack(
          children: [
            // Ambient subtle background gradient
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.15),
                    radius: 0.9,
                    colors: [
                      const Color(0xFF00E676).withValues(alpha: 0.08),
                      const Color(0xFF0D1B2A).withValues(alpha: 0.4),
                      const Color(0xFF070A0F),
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _animController,
                builder: (context, _) {
                  final scale = _animController.value < 0.6
                      ? _scaleAnimation.value
                      : _pulseAnimation.value;
                  final opacity = _fadeAnimation.value;

                  return Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: scale,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Glowing logo badge
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF132F23),
                                  Color(0xFF091611),
                                ],
                              ),
                              border: Border.all(
                                color: const Color(0xFF00E676).withValues(alpha: 0.5),
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E676).withValues(alpha: 0.28),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/kriya_logo.png',
                                width: 88,
                                height: 88,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const Center(
                                  child: Icon(
                                    Icons.code_rounded,
                                    size: 42,
                                    color: Color(0xFF00E676),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          // Brand Title
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'KRIYA',
                                style: TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3.5,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF00E676), Color(0xFF00B0FF)],
                                  ),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Text(
                                  'CODE',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.5,
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Mobile Code Studio',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              letterSpacing: 1.2,
                              color: Color(0xFF8899A6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Minimal pulsing progress indicator at the bottom
            Positioned(
              bottom: 48,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Color(0xFF161F2E),
                      valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00E676)),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
