import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../backend/live_studio/contracts/studio_ports.dart';
import '../../../../backend/live_studio/pool/pool_physics.dart';
import '../../../../backend/live_studio/pool/studio_pool.dart';
import '../../../../shared/theme/app_theme.dart';
import '../../../../backend/live_studio/media/studio_video_view.dart';
import '../shell/shell_widgets.dart' show StudioAvatar;
import 'pool_table_painter.dart';

class LivePoolLayer extends ConsumerStatefulWidget {
  const LivePoolLayer({
    super.key,
    required this.streamId,
    required this.room,
    this.isHost = false,
    this.onClose,
  });

  final String streamId;
  final StudioRoomPort room;
  final bool isHost;
  final VoidCallback? onClose;

  @override
  ConsumerState<LivePoolLayer> createState() => _LivePoolLayerState();
}

class _LivePoolLayerState extends ConsumerState<LivePoolLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  // Aiming state
  double _aimAngle = 0.0;
  double _aimPower = 0.45;
  double _spinX = 0.0;
  double _spinY = 0.0;
  int? _calledPocket;

  // Ball-in-hand drag state
  bool _isDraggingCueBall = false;
  Offset? _cueBallDragPixelPos;
  double? _cueBallDragNormX;
  double? _cueBallDragNormY;

  // Animation playback state
  bool _isAnimatingShot = false;
  Timer? _turnCountdownTimer;
  int _secondsLeft = 45;

  // Debounced aim telemetry broadcast
  Timer? _aimBroadcastDebounce;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _startCountdownWatchdog();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _turnCountdownTimer?.cancel();
    _aimBroadcastDebounce?.cancel();
    super.dispose();
  }

  void _startCountdownWatchdog() {
    _turnCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final pool = ref.read(studioPoolProvider(widget.streamId)).value;
      if (pool != null && pool.isInProgress) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final left = math.max(0, ((pool.turnEndsAtMs - now) / 1000).ceil());
        if (mounted && left != _secondsLeft) {
          setState(() => _secondsLeft = left);
        }
      }
    });
  }

  String get _currentUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  void _onTablePanUpdate(DragUpdateDetails details, Size tableSize, List<BallData> balls) {
    final cueBall = balls.firstWhere(
      (b) => b.id == 0,
      orElse: () => const BallData(id: 0, x: 0.5, y: 0.5),
    );

    final scaleX = tableSize.width / PoolConstants.tableWidth;
    final scaleY = tableSize.height / PoolConstants.tableHeight;
    final cuePixelPos = Offset(cueBall.x * scaleX, cueBall.y * scaleY);

    if (_isDraggingCueBall) {
      final normX = (details.localPosition.dx / scaleX).clamp(PoolConstants.minX, PoolConstants.maxX);
      final normY = (details.localPosition.dy / scaleY).clamp(PoolConstants.minY, PoolConstants.maxY);
      setState(() {
        _cueBallDragPixelPos = details.localPosition;
        _cueBallDragNormX = normX;
        _cueBallDragNormY = normY;
      });
      return;
    }

    final delta = details.localPosition - cuePixelPos;
    final angle = math.atan2(delta.dy, delta.dx);

    setState(() {
      _aimAngle = angle;
    });

    _scheduleAimBroadcast();
  }

  void _onTablePanDown(DragDownDetails details, Size tableSize, List<BallData> balls, bool ballInHand) {
    if (!ballInHand) return;
    final cueBall = balls.firstWhere(
      (b) => b.id == 0,
      orElse: () => const BallData(id: 0, x: 0.5, y: 0.5),
    );
    final scaleX = tableSize.width / PoolConstants.tableWidth;
    final scaleY = tableSize.height / PoolConstants.tableHeight;
    final cuePixelPos = Offset(cueBall.x * scaleX, cueBall.y * scaleY);

    if ((details.localPosition - cuePixelPos).distance < 36.0) {
      _isDraggingCueBall = true;
      _cueBallDragPixelPos = details.localPosition;
      HapticFeedback.selectionClick();
    }
  }

  void _onTablePanEnd(DragEndDetails details, bool ballInHand) {
    if (_isDraggingCueBall) {
      _isDraggingCueBall = false;
      if (_cueBallDragNormX != null && _cueBallDragNormY != null) {
        ref.read(studioPoolApiProvider).placeCueBall(
              widget.streamId,
              x: _cueBallDragNormX!,
              y: _cueBallDragNormY!,
            );
        HapticFeedback.lightImpact();
      }
      setState(() {
        _cueBallDragPixelPos = null;
        _cueBallDragNormX = null;
        _cueBallDragNormY = null;
      });
    }
  }

  void _scheduleAimBroadcast() {
    _aimBroadcastDebounce?.cancel();
    _aimBroadcastDebounce = Timer(const Duration(milliseconds: 60), () {
      ref.read(studioPoolApiProvider).broadcastAim(
            widget.streamId,
            angle: _aimAngle,
            power: _aimPower,
            spinX: _spinX,
            spinY: _spinY,
            cueBallX: _cueBallDragNormX,
            cueBallY: _cueBallDragNormY,
          );
    });
  }

  Future<void> _fireShot(PoolMatch match) async {
    if (_isAnimatingShot) return;

    HapticFeedback.mediumImpact();
    setState(() => _isAnimatingShot = true);

    try {
      await ref.read(studioPoolApiProvider).shoot(
            widget.streamId,
            angle: _aimAngle,
            power: _aimPower,
            spinX: _spinX,
            spinY: _spinY,
            calledPocket: _calledPocket,
          );

      setState(() => _calledPocket = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Shot error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAnimatingShot = false);
      }
    }
  }

  void _showEnglishSpinModal(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        double tempSpinX = _spinX;
        double tempSpinY = _spinY;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Cue Ball Spin & English', style: AppTheme.h2Style.copyWith(color: context.textPrimary)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Touch or drag red tip: Top = Follow, Bottom = Draw / Backspin, Sides = English',
                    style: AppTheme.captionStyle.copyWith(color: context.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // Interactive 2D Cue Ball English Pad
                  GestureDetector(
                    onPanUpdate: (d) {
                      final pos = d.localPosition - const Offset(80, 80);
                      const maxR = 64.0;
                      final normX = (pos.dx / maxR).clamp(-1.0, 1.0);
                      final normY = (pos.dy / maxR).clamp(-1.0, 1.0);

                      setModalState(() {
                        tempSpinX = normX;
                        tempSpinY = normY;
                      });
                      setState(() {
                        _spinX = normX;
                        _spinY = normY;
                      });
                      HapticFeedback.selectionClick();
                    },
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: context.border, width: 2.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Container(
                              width: 140,
                              height: 1.0,
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                          Center(
                            child: Container(
                              width: 1.0,
                              height: 140,
                              color: Colors.grey.withValues(alpha: 0.3),
                            ),
                          ),
                          Positioned(
                            left: 80 + (tempSpinX * 64) - 10,
                            top: 80 + (tempSpinY * 64) - 10,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFFEF4444),
                                border: Border.all(color: Colors.white, width: 2.0),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(120, 40),
                          side: BorderSide(color: context.border),
                        ),
                        onPressed: () {
                          setModalState(() {
                            tempSpinX = 0.0;
                            tempSpinY = 0.0;
                          });
                          setState(() {
                            _spinX = 0.0;
                            _spinY = 0.0;
                          });
                          HapticFeedback.lightImpact();
                        },
                        child: const Text('Center Cue'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(120, 40),
                          backgroundColor: AppColors.brandBlue,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Done', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _confirmCloseOrLeave(BuildContext context, PoolMatch match) {
    final isP = match.isPlayer(_currentUid);
    final title = widget.isHost ? 'Close Pool Table?' : (isP ? 'Resign / Leave Table?' : 'Leave Queue?');
    final desc = widget.isHost
        ? 'Closing the table will end the billiards session for all live viewers.'
        : (isP ? 'Leaving will forfeit the match to your opponent.' : 'You will be removed from the challenger queue.');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.surface,
        title: Text(title, style: AppTheme.h3Style.copyWith(color: context.textPrimary)),
        content: Text(desc, style: AppTheme.bodyStyle.copyWith(color: context.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: context.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              minimumSize: const Size(80, 38),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              if (widget.isHost) {
                ref.read(studioPoolApiProvider).closeMatch(widget.streamId);
                widget.onClose?.call();
              } else {
                ref.read(studioPoolApiProvider).leaveMatch(widget.streamId);
              }
            },
            child: const Text('Confirm', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final poolAsync = ref.watch(studioPoolProvider(widget.streamId));

    return poolAsync.when(
      data: (match) {
        if (match == null || match.isClosed) {
          return const SizedBox.shrink();
        }
        return _buildArena(context, match);
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error loading pool: $e', style: const TextStyle(color: Colors.redAccent)),
      ),
    );
  }

  Widget _buildArena(BuildContext context, PoolMatch match) {
    final isShooter = match.isShooter(_currentUid);
    final isPlayer = match.isPlayer(_currentUid);
    final cueBall = match.balls.firstWhere(
      (b) => b.id == 0,
      orElse: () => const BallData(id: 0, x: 0.5, y: 0.5),
    );

    final prediction = isShooter
        ? predictShotTrajectory(
            match.balls,
            _aimAngle,
            cueX: _cueBallDragNormX ?? cueBall.x,
            cueY: _cueBallDragNormY ?? cueBall.y,
          )
        : null;

    final onEightBall = match.groupOf(match.shooterUid) != null &&
        match.remainingGroupBalls(match.groupOf(match.shooterUid)!) == 0;

    return Container(
      color: Colors.black.withValues(alpha: 0.85),
      child: SafeArea(
        child: Column(
          children: [
            _buildTopSplitPlayersBar(context, match),
            const SizedBox(height: 8),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AspectRatio(
                    aspectRatio: 2.0 / 1.0,
                    child: LayoutBuilder(
                      builder: (ctx, constraints) {
                        final tableSize = Size(constraints.maxWidth, constraints.maxHeight);

                        return GestureDetector(
                          onPanDown: isShooter
                              ? (d) => _onTablePanDown(d, tableSize, match.balls, match.ballInHand)
                              : null,
                          onPanUpdate: isShooter
                              ? (d) => _onTablePanUpdate(d, tableSize, match.balls)
                              : null,
                          onPanEnd: isShooter
                              ? (d) => _onTablePanEnd(d, match.ballInHand)
                              : null,
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (ctx, _) {
                              return CustomPaint(
                                size: tableSize,
                                painter: PoolTablePainter(
                                  balls: match.balls,
                                  aimAngle: isShooter ? _aimAngle : null,
                                  aimPower: _aimPower,
                                  aimSpinX: _spinX,
                                  aimSpinY: _spinY,
                                  showAimRay: isShooter && !_isAnimatingShot,
                                  prediction: prediction,
                                  calledPocket: _calledPocket ?? match.calledPocket,
                                  ballInHand: match.ballInHand && isShooter,
                                  cueBallDragging: _isDraggingCueBall,
                                  cueBallDragPos: _cueBallDragPixelPos,
                                  pocketAnimationProgress: _pulseController.value,
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (isShooter) ...[
              _buildShooterControls(context, match, onEightBall),
            ] else ...[
              _buildSpectatorControls(context, match, isPlayer),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopSplitPlayersBar(BuildContext context, PoolMatch match) {
    final p1Active = match.shooterUid == match.p1Uid;
    final p2Active = match.p2Uid != null && match.shooterUid == match.p2Uid;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: context.surface.withValues(alpha: 0.95),
        border: Border(bottom: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.brandBlue,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '8-BALL POOL',
                      style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Race to ${math.max(1, (match.bestOf / 2).ceil())} · Frame ${match.rackNumber}',
                    style: AppTheme.captionStyle.copyWith(fontWeight: FontWeight.w700, color: context.textPrimary),
                  ),
                ],
              ),
              Row(
                children: [
                  if (match.isInProgress)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _secondsLeft < 10
                            ? const Color(0xFFEF4444).withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _secondsLeft < 10 ? const Color(0xFFEF4444) : Colors.transparent,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.timer_outlined,
                            size: 13,
                            color: _secondsLeft < 10 ? const Color(0xFFEF4444) : context.textPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_secondsLeft}s',
                            style: AppTheme.captionStyle.copyWith(
                              fontWeight: FontWeight.w800,
                              color: _secondsLeft < 10 ? const Color(0xFFEF4444) : context.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => _confirmCloseOrLeave(context, match),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildPlayerCameraPortion(
                  context,
                  uid: match.p1Uid,
                  name: match.p1Name,
                  avatarUrl: match.p1Avatar,
                  score: match.p1Score,
                  group: match.p1Group,
                  isActiveShooter: p1Active,
                  match: match,
                  alignRight: false,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Column(
                  children: [
                    Text(
                      '${match.p1Score} - ${match.p2Score}',
                      style: AppTheme.h2Style.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppColors.brandPink,
                      ),
                    ),
                    Text(
                      match.tableState.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
                        color: match.tableState == 'open' ? Colors.amber : AppColors.brandBlue,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: match.p2Uid != null
                    ? _buildPlayerCameraPortion(
                        context,
                        uid: match.p2Uid!,
                        name: match.p2Name ?? 'Player 2',
                        avatarUrl: match.p2Avatar ?? '',
                        score: match.p2Score,
                        group: match.p2Group,
                        isActiveShooter: p2Active,
                        match: match,
                        alignRight: true,
                      )
                    : _buildWaitingP2Slot(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerCameraPortion(
    BuildContext context, {
    required String uid,
    required String name,
    required String avatarUrl,
    required int score,
    required String? group,
    required bool isActiveShooter,
    required PoolMatch match,
    required bool alignRight,
  }) {
    final cam = widget.room.cameraOf(uid);
    final avatar = StudioAvatar(
      name: name,
      url: avatarUrl,
      size: 48,
      fill: context.surfaceMid,
    );

    final remaining = group != null ? match.remainingGroupBalls(group) : 7;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: isActiveShooter
            ? AppColors.brandBlue.withValues(alpha: 0.12)
            : context.surfaceMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActiveShooter ? AppColors.brandBlue : context.border,
          width: isActiveShooter ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (alignRight) ...[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    name,
                    style: AppTheme.h3Style.copyWith(fontSize: 12.5, color: context.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _buildRemainingBallsIndicator(group, remaining),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isActiveShooter ? AppColors.brandPink : context.border,
                    width: 1.5,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: cam != null ? StudioVideoView(cam, placeholder: avatar) : avatar,
                ),
              ),
              if (isActiveShooter)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF22C55E),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          if (!alignRight) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppTheme.h3Style.copyWith(fontSize: 12.5, color: context.textPrimary),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  _buildRemainingBallsIndicator(group, remaining),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRemainingBallsIndicator(String? group, int remaining) {
    if (group == null) {
      return Text('OPEN', style: TextStyle(color: Colors.amber.shade400, fontSize: 10, fontWeight: FontWeight.w700));
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: group == 'solids' ? const Color(0xFFFACC15) : Colors.white,
            border: Border.all(
              color: group == 'stripes' ? const Color(0xFF2563EB) : Colors.transparent,
              width: 1.5,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          remaining == 0 ? 'ON 8' : '$remaining ${group.toUpperCase()}',
          style: TextStyle(
            color: remaining == 0 ? AppColors.brandPink : Colors.grey.shade400,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingP2Slot(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: context.surfaceMid.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.border, width: 1.0),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.person_add_alt_1_outlined, size: 18, color: AppColors.brandPink),
          const SizedBox(width: 6),
          Text(
            'Waiting for P2...',
            style: AppTheme.captionStyle.copyWith(color: AppColors.brandPink, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildShooterControls(BuildContext context, PoolMatch match, bool onEightBall) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onEightBall) ...[
            Row(
              children: [
                Text(
                  'CALL POCKET:',
                  style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: AppColors.brandPink, letterSpacing: 0.6),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: List.generate(6, (idx) {
                        final isSelected = _calledPocket == idx || match.calledPocket == idx;
                        final pocketNames = ['Top-L', 'Top-M', 'Top-R', 'Bot-R', 'Bot-M', 'Bot-L'];
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ChoiceChip(
                            label: Text(pocketNames[idx], style: const TextStyle(fontSize: 11)),
                            selected: isSelected,
                            selectedColor: AppColors.brandPink,
                            onSelected: (sel) {
                              if (sel) {
                                setState(() => _calledPocket = idx);
                                ref.read(studioPoolApiProvider).callPocket(widget.streamId, idx);
                                HapticFeedback.selectionClick();
                              }
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              IconButton(
                style: IconButton.styleFrom(
                  backgroundColor: context.surfaceMid,
                  padding: const EdgeInsets.all(10),
                ),
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.blur_circular, size: 24),
                    if (_spinX != 0.0 || _spinY != 0.0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: 'Cue Spin & English',
                onPressed: () => _showEnglishSpinModal(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('POWER', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: context.textSecondary)),
                        Text('${(_aimPower * 100).toInt()}%', style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w800, color: context.textPrimary)),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 6,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                        activeTrackColor: AppColors.brandBlue,
                        inactiveTrackColor: context.surfaceMid,
                        thumbColor: Colors.white,
                      ),
                      child: Slider(
                        value: _aimPower,
                        min: 0.05,
                        max: 1.0,
                        onChanged: (v) {
                          setState(() => _aimPower = v);
                          _scheduleAimBroadcast();
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPink,
                  minimumSize: const Size(96, 46),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isAnimatingShot ? null : () => _fireShot(match),
                child: _isAnimatingShot
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.sports_baseball, size: 16, color: Colors.white),
                          SizedBox(width: 4),
                          Text('SHOOT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSpectatorControls(BuildContext context, PoolMatch match, bool isPlayer) {
    final queue = match.challengerQueue;
    final isQueued = queue.any((q) => q.uid == _currentUid);
    final queueIndex = queue.indexWhere((q) => q.uid == _currentUid);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.surface,
        border: Border(top: BorderSide(color: context.border, width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  match.isGameOver
                      ? 'Game Over — Winner: ${match.winnerUid == match.p1Uid ? match.p1Name : (match.p2Name ?? "P2")}'
                      : (isPlayer
                          ? 'Waiting for opponent shot...'
                          : (isQueued
                              ? 'Queued for next game (#${queueIndex + 1})'
                              : 'Live Spectator Mode')),
                  style: AppTheme.h3Style.copyWith(fontSize: 12.5, color: context.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                if (match.winReason != null && match.isGameOver)
                  Text(
                    match.winReason!,
                    style: AppTheme.captionStyle.copyWith(color: AppColors.brandPink),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (match.isGameOver && (isPlayer || widget.isHost))
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brandBlue,
                minimumSize: const Size(110, 40),
              ),
              onPressed: () {
                ref.read(studioPoolApiProvider).rematch(widget.streamId);
                HapticFeedback.lightImpact();
              },
              child: const Text('Next Rack', style: TextStyle(color: Colors.white)),
            )
          else if (!isPlayer) ...[
            if (isQueued)
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(110, 40),
                  side: BorderSide(color: context.border),
                ),
                onPressed: () {
                  ref.read(studioPoolApiProvider).leaveMatch(widget.streamId);
                  HapticFeedback.lightImpact();
                },
                child: const Text('Leave Queue'),
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brandPink,
                  minimumSize: const Size(130, 40),
                ),
                icon: const Icon(Icons.videocam_outlined, size: 18, color: Colors.white),
                label: Text(
                  match.p2Uid == null ? 'Play Live (Cam)' : 'Queue Next',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                ),
                onPressed: () {
                  ref.read(studioPoolApiProvider).joinMatch(widget.streamId);
                  HapticFeedback.mediumImpact();
                },
              ),
          ],
        ],
      ),
    );
  }
}
