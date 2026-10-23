import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/theme/app_theme.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with SingleTickerProviderStateMixin {
  bool _isRecording = false;

  // Capture Controls State
  String _resolution = '1080p';
  String _fps = '60fps';
  String _mode = 'Video';
  bool _flash = false;
  int _timerSeconds = 0;
  double _speed = 1.0;
  bool _grid = false;
  bool _stabilization = true;
  double _beautyLevel = 0.0;

  // Exposure and Focus (simulated)
  double _exposure = 0.5;
  Offset? _focusPoint;
  bool _showExposureSlider = false;

  final List<String> _modes = ['Photo', 'Video', 'Dual', 'Screen'];
  final List<String> _speedOptions = ['0.3x', '0.5x', '1x', '2x', '3x'];

  // Timer animation
  int _countdown = 0;
  Timer? _countdownTimer;

  late AnimationController _recordPulseController;

  @override
  void initState() {
    super.initState();
    _recordPulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _recordPulseController.dispose();
    super.dispose();
  }

  void _startRecordingProcess() {
    if (_timerSeconds > 0) {
      setState(() {
        _countdown = _timerSeconds;
      });
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          _countdown--;
          if (_countdown <= 0) {
            timer.cancel();
            _isRecording = true;
          }
        });
      });
    } else {
      setState(() {
        _isRecording = true;
      });
    }
  }

  void _stopRecordingProcess() {
    setState(() {
      _isRecording = false;
    });
    // Go to Editor
    context.push('/upload/global');
  }

  void _onScreenTap(TapDownDetails details) {
    setState(() {
      _focusPoint = details.localPosition;
      _showExposureSlider = true;
    });
    // Hide exposure slider after a few seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _showExposureSlider) {
        setState(() {
          _showExposureSlider = false;
          _focusPoint = null;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Simulated Camera Viewfinder
          GestureDetector(
            onTapDown: _onScreenTap,
            child: Container(
              color: Colors.grey.shade900,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const Center(
                    child: Icon(
                      Icons.camera_alt,
                      color: Colors.white24,
                      size: 64,
                    ),
                  ),
                  // Grid Overlay
                  if (_grid) _buildGridOverlay(),

                  // Focus & Exposure Overlay
                  if (_focusPoint != null)
                    Positioned(
                      left: _focusPoint!.dx - 40,
                      top: _focusPoint!.dy - 40,
                      child: _buildFocusRing(),
                    ),

                  // Beauty Filter Overlay (simulated)
                  if (_beautyLevel > 0)
                    Container(
                      color: Colors.pinkAccent.withValues(
                        alpha: _beautyLevel * 0.1,
                      ),
                    ),

                  // Stabilization Indicator
                  if (_stabilization)
                    const Positioned(
                      top: 100,
                      left: 16,
                      child: Icon(
                        Icons.videocam_outlined,
                        color: Colors.amber,
                        size: 20,
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Countdown Overlay
          if (_countdown > 0)
            Center(
              child: Text(
                '$_countdown',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 120,
                  fontWeight: FontWeight.w900,
                  shadows: [Shadow(color: Colors.black, blurRadius: 10)],
                ),
              ),
            ),

          // 2. Top Controls
          if (!_isRecording && _countdown == 0)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8.0,
                    vertical: 8.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () => context.pop(),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildTopAction(
                            _flash ? Icons.flash_on : Icons.flash_off,
                            _flash ? 'Flash On' : 'Flash Off',
                            onTap: () => setState(() => _flash = !_flash),
                          ),
                          _buildTopAction(
                            _timerSeconds == 0 ? Icons.timer_off : Icons.timer,
                            _timerSeconds == 0 ? 'Off' : '${_timerSeconds}s',
                            onTap: () {
                              setState(() {
                                if (_timerSeconds == 0) {
                                  _timerSeconds = 3;
                                } else if (_timerSeconds == 3) {
                                  _timerSeconds = 10;
                                } else {
                                  _timerSeconds = 0;
                                }
                              });
                            },
                          ),
                          _buildTopAction(
                            Icons.hd,
                            _resolution,
                            onTap: () {
                              setState(() {
                                _resolution = _resolution == '1080p'
                                    ? '4K'
                                    : (_resolution == '4K' ? '720p' : '1080p');
                              });
                            },
                          ),
                          _buildTopAction(
                            Icons.shutter_speed,
                            _fps,
                            onTap: () {
                              setState(() {
                                _fps = _fps == '30fps'
                                    ? '60fps'
                                    : (_fps == '60fps' ? '24fps' : '30fps');
                              });
                            },
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.settings,
                          color: Colors.white,
                          size: 28,
                        ),
                        onPressed: () {
                          // TODO: Open advanced settings modal
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 3. Right Controls
          if (!_isRecording && _countdown == 0)
            Positioned(
              right: 16,
              top: 140,
              child: Column(
                children: [
                  _buildRightControl(Icons.cameraswitch, 'Flip', () {}),
                  _buildRightControl(Icons.speed, '${_speed}x', () {
                    // Cycle speed
                    int idx = _speedOptions.indexOf('${_speed}x');
                    if (idx == -1) idx = 2; // 1x
                    idx = (idx + 1) % _speedOptions.length;
                    setState(() {
                      _speed = double.parse(
                        _speedOptions[idx].replaceAll('x', ''),
                      );
                    });
                  }),
                  _buildRightControl(
                    Icons.face_retouching_natural,
                    'Beauty',
                    () {
                      setState(() {
                        _beautyLevel = _beautyLevel == 0
                            ? 0.5
                            : (_beautyLevel == 0.5 ? 1.0 : 0);
                      });
                    },
                  ),
                  _buildRightControl(Icons.grid_3x3, 'Grid', () {
                    setState(() => _grid = !_grid);
                  }),
                  _buildRightControl(Icons.videocam_outlined, 'Stable', () {
                    setState(() => _stabilization = !_stabilization);
                  }),
                ],
              ),
            ),

          // 4. Bottom Controls (Record & Modes)
          if (_countdown == 0)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  // Modes
                  if (!_isRecording)
                    SizedBox(
                      height: 40,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _modes.length,
                        itemBuilder: (context, index) {
                          final mode = _modes[index];
                          final isSelected = mode == _mode;
                          return GestureDetector(
                            onTap: () => setState(() => _mode = mode),
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: Text(
                                mode,
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.white54,
                                  fontWeight: isSelected
                                      ? FontWeight.w900
                                      : FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 20),
                  // Record Button Area
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      if (!_isRecording)
                        _buildBottomAction(Icons.photo_library, 'Upload')
                      else
                        const SizedBox(
                          width: 60,
                        ), // Placeholder to keep center alignment

                      GestureDetector(
                        onTap: () {
                          if (_mode == 'Video' || _mode == 'Dual') {
                            if (_isRecording) {
                              _stopRecordingProcess();
                            } else {
                              _startRecordingProcess();
                            }
                          } else {
                            // Photo mode
                            context.push('/upload/global');
                          }
                        },
                        child: AnimatedBuilder(
                          animation: _recordPulseController,
                          builder: (context, child) {
                            return Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _isRecording
                                      ? Colors.red.withValues(
                                          alpha: 0.5 +
                                              (_recordPulseController.value *
                                                  0.5),
                                        )
                                      : Colors.white,
                                  width: 4,
                                ),
                              ),
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  width: _isRecording ? 30 : 64,
                                  height: _isRecording ? 30 : 64,
                                  decoration: BoxDecoration(
                                    color: AppColors.brandBlue,
                                    borderRadius: BorderRadius.circular(
                                      _isRecording ? 8 : 32,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      if (!_isRecording)
                        _buildBottomAction(
                          Icons.check,
                          'Done',
                          onTap: () {
                            context.push('/upload/global');
                          },
                        )
                      else
                        const SizedBox(width: 60),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopAction(IconData icon, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightControl(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomAction(
    IconData icon,
    String label, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridOverlay() {
    return Stack(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Container(width: 1, color: Colors.white30),
            Container(width: 1, color: Colors.white30),
          ],
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Container(height: 1, color: Colors.white30),
            Container(height: 1, color: Colors.white30),
          ],
        ),
      ],
    );
  }

  Widget _buildFocusRing() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        border: Border.all(color: Colors.amber, width: 2),
        shape: BoxShape.circle,
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Center(child: Container(width: 4, height: 4, color: Colors.amber)),
          if (_showExposureSlider)
            Positioned(
              right: -30,
              top: 0,
              bottom: 0,
              child: RotatedBox(
                quarterTurns: 3,
                child: Slider(
                  value: _exposure,
                  min: 0.0,
                  max: 1.0,
                  activeColor: Colors.amber,
                  inactiveColor: Colors.white30,
                  onChanged: (val) {
                    setState(() => _exposure = val);
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
