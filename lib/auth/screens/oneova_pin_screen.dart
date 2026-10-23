import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/pin_auth_service.dart';
import '../../shared/theme/app_theme.dart';

enum PinScreenMode { verify, setup }

class OneovaPinScreen extends ConsumerStatefulWidget {
  final PinScreenMode mode;
  final VoidCallback? onSuccess;

  const OneovaPinScreen({
    super.key,
    this.mode = PinScreenMode.verify,
    this.onSuccess,
  });

  @override
  ConsumerState<OneovaPinScreen> createState() => _OneovaPinScreenState();
}

class _OneovaPinScreenState extends ConsumerState<OneovaPinScreen> with SingleTickerProviderStateMixin {
  String _pin = '';
  String _confirmPin = '';
  bool _isConfirming = false;
  bool _hasError = false;
  
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -10), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: -10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -10, end: 10), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 10, end: 0), weight: 1),
    ]).animate(_shakeController);
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  void _onKeypadPressed(String val) {
    if (_hasError) {
      setState(() => _hasError = false);
    }
    
    if (_pin.length < 6) {
      setState(() => _pin += val);
      if (_pin.length == 6) {
        _onPinComplete();
      }
    }
  }

  void _onBackspacePressed() {
    if (_hasError) {
      setState(() => _hasError = false);
    }
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  Future<void> _onPinComplete() async {
    final pinAuthService = ref.read(pinAuthServiceProvider);

    if (widget.mode == PinScreenMode.verify) {
      final result = await pinAuthService.verifyPin(_pin);
      if (result.isSuccess) {
        if (widget.onSuccess != null) {
          widget.onSuccess!();
        } else {
          Navigator.pop(context, true);
        }
      } else if (result.isLockedOut) {
        _triggerError();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Too many attempts. Try again in ${result.lockoutMinutes} min.',
              ),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        _triggerError();
        if (mounted && result.remainingAttempts > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Incorrect PIN. ${result.remainingAttempts} attempts remaining.'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } else {
      // Setup Mode
      if (!_isConfirming) {
        setState(() {
          _confirmPin = _pin;
          _pin = '';
          _isConfirming = true;
        });
      } else {
        if (_pin == _confirmPin) {
          await pinAuthService.setPin(_pin);
          if (widget.onSuccess != null) {
            widget.onSuccess!();
          } else {
            Navigator.pop(context, true);
          }
        } else {
          _triggerError();
        }
      }
    }
  }

  void _triggerError() {
    setState(() {
      _hasError = true;
      _pin = '';
    });
    _shakeController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    String titleText = widget.mode == PinScreenMode.verify ? 'Enter PIN' : 'Set PIN';
    if (widget.mode == PinScreenMode.setup && _isConfirming) {
      titleText = 'Confirm PIN';
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, false),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Icon(Icons.lock_outline, size: 48, color: AppColors.brandBlue),
            const SizedBox(height: 16),
            Text(
              titleText,
              style: AppTheme.h1Style.copyWith(fontSize: 24),
            ),
            const SizedBox(height: 8),
            Text(
              _hasError ? (widget.mode == PinScreenMode.setup ? 'PINs do not match' : 'Incorrect PIN') : 'Enter your 6-digit code',
              style: AppTheme.bodyStyle.copyWith(
                color: _hasError ? theme.colorScheme.error : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 40),
            AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(_shakeAnimation.value, 0),
                  child: child,
                );
              },
              child: _buildPinDots(),
            ),
            const Spacer(),
            _buildKeypad(),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPinDots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(6, (index) {
        final isFilled = index < _pin.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled 
                ? (_hasError ? Theme.of(context).colorScheme.error : AppColors.brandBlue)
                : Colors.transparent,
            border: Border.all(
              color: isFilled 
                  ? (_hasError ? Theme.of(context).colorScheme.error : AppColors.brandBlue)
                  : Theme.of(context).colorScheme.outline,
              width: 2,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildKeypad() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('1'),
              _buildKeypadButton('2'),
              _buildKeypadButton('3'),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('4'),
              _buildKeypadButton('5'),
              _buildKeypadButton('6'),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildKeypadButton('7'),
              _buildKeypadButton('8'),
              _buildKeypadButton('9'),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const SizedBox(width: 70), // Empty space for alignment
              _buildKeypadButton('0'),
              SizedBox(
                width: 70,
                height: 70,
                child: IconButton(
                  onPressed: _onBackspacePressed,
                  icon: const Icon(Icons.backspace_outlined, size: 28),
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKeypadButton(String text) {
    return InkWell(
      onTap: () => _onKeypadPressed(text),
      customBorder: const CircleBorder(),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).colorScheme.surface,
        ),
        alignment: Alignment.center,
        child: Text(
          text,
          style: AppTheme.h2Style.copyWith(fontSize: 28),
        ),
      ),
    );
  }
}
