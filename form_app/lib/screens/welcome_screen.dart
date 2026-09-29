import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../services/desktop_connection_service.dart';
import '../services/form_app_config_service.dart';
import '../services/persistent_form_service.dart';
import '../theme/app_theme.dart';
import '../widgets/responsive_layout.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  Timer? _resetTimer;
  Timer? _sleepTimer;
  bool _isSleeping = false;

  /// Custom video file paths from FormAppConfigService.
  /// Empty means use the default bundled video.
  List<String> _videoPlaylist = [];

  /// Current index in the video playlist.
  int _currentVideoIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadConfigAndInitVideo();
    _startTimers();
  }

  /// Load custom assets config, then start the video.
  Future<void> _loadConfigAndInitVideo() async {
    await FormAppConfigService.instance.init();
    _videoPlaylist = FormAppConfigService.instance.getVideoPaths();
    _currentVideoIndex = 0;
    _initVideo();
  }

  void _startTimers() {
    _stopTimers();
    // 10-minute reset timer
    _resetTimer = Timer(const Duration(minutes: 10), () {
      if (mounted) {
        PersistentFormService.instance.clear();
      }
    });

    // 1-hour sleep timer
    _sleepTimer = Timer(const Duration(minutes: 30), () {
      if (mounted) {
        setState(() => _isSleeping = true);
        _videoController?.pause();
      }
    });
  }

  void _stopTimers() {
    _resetTimer?.cancel();
    _sleepTimer?.cancel();
  }

  void _initVideo() {
    if (_isSleeping) return;

    if (_videoPlaylist.isNotEmpty) {
      // Use custom video files from the playlist
      final path = _videoPlaylist[_currentVideoIndex];
      _videoController = VideoPlayerController.file(File(path));
    } else {
      // Fallback to default bundled video
      _videoController =
          VideoPlayerController.asset('assets/default-clinic-avp.mp4');
    }

    _videoController!.initialize().then((_) {
      if (!mounted) return;
      _videoController!.setVolume(0.0);

      if (_videoPlaylist.length > 1) {
        // Playlist mode: don't loop individual videos,
        // instead advance to next on completion
        _videoController!.setLooping(false);
        _videoController!.addListener(_onVideoProgress);
      } else {
        // Single video (custom or default): loop it
        _videoController!.setLooping(true);
      }

      _videoController!.play();
      setState(() => _videoInitialized = true);
    });
  }

  /// Listener for playlist advancement.
  void _onVideoProgress() {
    if (_videoController == null) return;
    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;

    if (duration > Duration.zero && position >= duration) {
      // Current video finished — advance to next
      _advanceToNextVideo();
    }
  }

  /// Dispose current video and play the next one in the playlist.
  void _advanceToNextVideo() {
    _videoController?.removeListener(_onVideoProgress);
    _videoController?.dispose();
    _videoController = null;
    _videoInitialized = false;

    _currentVideoIndex = (_currentVideoIndex + 1) % _videoPlaylist.length;
    _initVideo();
  }

  Future<void> _handleTap() async {
    if (_isSleeping) {
      setState(() => _isSleeping = false);
      _loadConfigAndInitVideo();
      _startTimers();
      return;
    }

    // Verify active connection to the desktop server before proceeding
    final isConnected =
        await DesktopConnectionService.instance.checkConnection();
    if (!mounted) return;

    if (!isConnected) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: AppTheme.danger),
              SizedBox(width: 12),
              Text('Connection Lost'),
            ],
          ),
          content: const Text(
            'The form app is no longer connected to the desktop server. Please return to the setup screen to reconnect.',
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushNamedAndRemoveUntil(
                  context,
                  '/help',
                  (route) => false,
                );
              },
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Return to Setup'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
      return;
    }

    if (PersistentFormService.instance.hasData) {
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.history_rounded, color: Color(0xFF1B4697)),
              SizedBox(width: 12),
              Text('Resume Progress?'),
            ],
          ),
          content: const Text(
            'We found an unsaved form. Would you like to continue where you left off or start a new form?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'reset'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Start New'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'resume'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B4697),
              ),
              child: const Text('Resume'),
            ),
          ],
        ),
      );

      if (choice == 'reset') {
        PersistentFormService.instance.clear();
      } else if (choice == null) {
        return; // Dialog cancelled or dismissed
      }
    }

    // Fully dispose video to release hardware codec buffers for the camera
    _videoController?.removeListener(_onVideoProgress);
    await _videoController?.dispose();
    _videoController = null;
    _videoInitialized = false;

    if (!mounted) return;

    final route = PersistentFormService.instance.isEmpty
        ? '/id-method'
        : '/form';
    await Navigator.pushNamed(context, route);

    // Re-initialize video when coming back
    if (mounted) {
      _loadConfigAndInitVideo();
      _startTimers(); // Restart timers when returning to welcome screen
    }
  }

  @override
  void dispose() {
    _stopTimers();
    _videoController?.removeListener(_onVideoProgress);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isSleeping) {
      return GestureDetector(
        onTap: _handleTap,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TAP ANYWHERE TO WAKE',
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 24,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 16),
                Opacity(
                  opacity: 0.3,
                  child: Image.asset(
                    'assets/app-logo-white.png',
                    height: 30,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final isMobile = ResponsiveLayout.isMobile(context);
    final screenWidth = MediaQuery.of(context).size.width;

    return GestureDetector(
      onTap: _handleTap,
      child: Scaffold(
        extendBody: false,
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            image: DecorationImage(
              image: FormAppConfigService.instance.getBackgroundProvider() ??
                  const AssetImage('assets/welcome-background.png'),
              fit: BoxFit.cover,
            ),
          ),
          child: Column(
            children: [
              // Upper portion: Logo (left) and Date/Time (right)
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isMobile ? 20 : 32,
                  vertical: isMobile ? 30 : 40,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Upper left: Logo (custom or default)
                    Builder(
                      builder: (context) {
                        final logoProvider =
                            FormAppConfigService.instance.getLogoProvider();
                        if (logoProvider != null) {
                          return Image(
                            image: logoProvider,
                            height: isMobile ? 40 : 80,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Image.asset(
                              'assets/app-logo-colored.png',
                              height: isMobile ? 40 : 80,
                              fit: BoxFit.contain,
                            ),
                          );
                        }
                        return Image.asset(
                          'assets/app-logo-colored.png',
                          height: isMobile ? 40 : 80,
                          fit: BoxFit.contain,
                        );
                      },
                    ),
                    // Upper right: Date and Time
                    StreamBuilder(
                      stream: Stream.periodic(const Duration(seconds: 1)),
                      builder: (context, snapshot) {
                        final now = DateTime.now();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('EEEE, MMMM d, yyyy').format(now),
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 14 : 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('hh:mm a').format(now),
                              style: GoogleFonts.inter(
                                fontSize: isMobile ? 14 : 18,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 2),

              // Center texts
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    Text(
                      'OUR LADY OF PERPETUAL SUCCOR COLLEGE',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 12 : 18,
                        fontWeight: FontWeight.normal,
                        color: Colors.white,
                        letterSpacing: isMobile ? 1.5 : 3.0,
                      ),
                    ),
                    Text(
                      'SCHOOL CLINIC SYSTEM',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: isMobile ? 28 : 48,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: isMobile ? 1.0 : 2.0,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Video player area
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                width: isMobile ? screenWidth : 640,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                        width: 2,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: _videoInitialized && _videoController != null
                          ? VideoPlayer(_videoController!)
                          : const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // POWERED BY + App Logo White
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'POWERED BY: ',
                    style: GoogleFonts.inter(
                      fontSize: isMobile ? 10 : 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.8),
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Image.asset(
                    'assets/app-logo-white.png',
                    height: isMobile ? 25 : 40,
                    fit: BoxFit.contain,
                  ),
                ],
              ),

              const Spacer(flex: 3),

              // Bottom white bar with animated text
              Container(
                width: double.infinity,
                color: Colors.white,
                padding: EdgeInsets.symmetric(vertical: isMobile ? 20 : 32),
                child: Center(
                  child: AnimatedTextKit(
                    animatedTexts: [
                      TyperAnimatedText(
                        'TAP ANYWHERE TO CONTINUE',
                        textStyle: GoogleFonts.inter(
                          fontSize: isMobile ? 18 : 30,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF1B4697),
                          letterSpacing: 1.2,
                        ),
                        speed: const Duration(milliseconds: 60),
                        textAlign: TextAlign.left,
                      ),
                    ],
                    repeatForever: true,
                    pause: const Duration(seconds: 4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
