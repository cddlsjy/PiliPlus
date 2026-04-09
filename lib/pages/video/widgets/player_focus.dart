import 'dart:async';
import 'dart:io' show exit, Platform;
import 'dart:math' as math;

import 'package:PiliPlus/pages/common/common_intro_controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/plugin/pl_player/controller.dart';
import 'package:PiliPlus/utils/platform_utils.dart';
import 'package:PiliPlus/utils/storage.dart';
import 'package:PiliPlus/utils/storage_key.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyUpEvent, LogicalKeyboardKey, HardwareKeyboard;
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class PlayerFocus extends StatefulWidget {
  const PlayerFocus({
    super.key,
    required this.child,
    required this.plPlayerController,
    this.introController,
    required this.onSendDanmaku,
    this.canPlay,
    this.onSkipSegment,
    this.onRefresh,
  });

  final Widget child;
  final PlPlayerController plPlayerController;
  final CommonIntroController? introController;
  final VoidCallback onSendDanmaku;
  final ValueGetter<bool>? canPlay;
  final ValueGetter<bool>? onSkipSegment;
  final VoidCallback? onRefresh;

  @override
  State<PlayerFocus> createState() => _PlayerFocusState();
}

class _PlayerFocusState extends State<PlayerFocus> {
  /// 遥控器上下键双击切换视频的定时器
  Timer? _upDoublePressTimer;
  Timer? _downDoublePressTimer;
  static const _doublePressDuration = Duration(milliseconds: 300);
  bool _upPressed = false;
  bool _downPressed = false;

  @override
  void dispose() {
    _upDoublePressTimer?.cancel();
    _downDoublePressTimer?.cancel();
    super.dispose();
  }

  static bool _shouldHandle(LogicalKeyboardKey logicalKey) {
    return logicalKey == LogicalKeyboardKey.tab ||
        logicalKey == LogicalKeyboardKey.arrowLeft ||
        logicalKey == LogicalKeyboardKey.arrowRight ||
        logicalKey == LogicalKeyboardKey.arrowUp ||
        logicalKey == LogicalKeyboardKey.arrowDown ||
        logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.gameButtonA ||
        logicalKey == LogicalKeyboardKey.ok;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        final handled = _handleKey(event);
        if (handled || _shouldHandle(event.logicalKey)) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: widget.child,
    );
  }

  bool get isFullScreen => widget.plPlayerController.isFullScreen.value;
  bool get hasPlayer => widget.plPlayerController.videoPlayerController != null;

  void _setVolume({required bool isIncrease}) {
    final volume = isIncrease
        ? math.min(
            PlPlayerController.maxVolume,
            widget.plPlayerController.volume.value + 0.1,
          )
        : math.max(0.0, widget.plPlayerController.volume.value - 0.1);
    widget.plPlayerController.setVolume(volume);
  }

  void _updateVolume(KeyEvent event, {required bool isIncrease}) {
    if (event is KeyDownEvent) {
      if (hasPlayer) {
        _setVolume(isIncrease: isIncrease);
        widget.plPlayerController
          ..longPressTimer?.cancel()
          ..longPressTimer = Timer.periodic(
            const Duration(milliseconds: 150),
            (_) => _setVolume(isIncrease: isIncrease),
          );
      }
    } else if (event is KeyUpEvent) {
      widget.plPlayerController.cancelLongPressTimer();
    }
  }

  /// 处理遥控器上键
  void _handleRemoteUp() {
    if (_upPressed) {
      // 双击上键 - 切换上一个视频
      _upDoublePressTimer?.cancel();
      _upPressed = false;
      if (widget.introController != null) {
        if (!widget.introController!.prevPlay()) {
          SmartDialog.showToast('已经是第一个了');
        }
      }
    } else {
      _upPressed = true;
      _upDoublePressTimer?.cancel();
      _upDoublePressTimer = Timer(_doublePressDuration, () {
        _upPressed = false;
        // 单击上键 - 增加音量
        if (hasPlayer) {
          _setVolume(isIncrease: true);
        }
      });
    }
  }

  /// 处理遥控器下键
  void _handleRemoteDown() {
    if (_downPressed) {
      // 双击下键 - 切换下一个视频
      _downDoublePressTimer?.cancel();
      _downPressed = false;
      if (widget.introController != null) {
        if (!widget.introController!.nextPlay()) {
          SmartDialog.showToast('已经是最后一个了');
        }
      }
    } else {
      _downPressed = true;
      _downDoublePressTimer?.cancel();
      _downDoublePressTimer = Timer(_doublePressDuration, () {
        _downPressed = false;
        // 单击下键 - 减小音量
        if (hasPlayer) {
          _setVolume(isIncrease: false);
        }
      });
    }
  }

  /// 处理遥控器OK键 - 暂停/恢复播放
  void _handleRemoteOk() {
    if (hasPlayer) {
      widget.plPlayerController.onDoubleTapCenter();
      SmartDialog.showToast(
        widget.plPlayerController.playerStatus.isPlaying ? '已暂停' : '已播放'
      );
    }
  }

  bool _handleKey(KeyEvent event) {
    final key = event.logicalKey;

    final isKeyQ = key == LogicalKeyboardKey.keyQ;
    if (isKeyQ || key == LogicalKeyboardKey.keyR) {
      if (HardwareKeyboard.instance.isMetaPressed) {
        if (isKeyQ && Platform.isMacOS) {
          exit(0);
        }
        return true;
      }
      if (event is KeyDownEvent) {
        if (widget.plPlayerController.isLive) {
          widget.onRefresh?.call();
        } else {
          widget.introController!.onStartTriple();
        }
      } else if (event is KeyUpEvent && !widget.plPlayerController.isLive) {
        widget.introController!.onCancelTriple(isKeyQ);
      }
      return true;
    }

    final isArrowUp = key == LogicalKeyboardKey.arrowUp;
    if (isArrowUp || key == LogicalKeyboardKey.arrowDown) {
      // 上下键：单击调节音量，双击切换视频
      if (event is KeyDownEvent) {
        if (isArrowUp) {
          _handleRemoteUp();
        } else {
          _handleRemoteDown();
        }
      }
      return true;
    }

    // 遥控器OK键处理 - 暂停/恢复播放
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA ||
        key == LogicalKeyboardKey.ok) {
      if (event is KeyDownEvent) {
        _handleRemoteOk();
      }
      return true;
    }

    if (key == LogicalKeyboardKey.arrowRight) {
      if (!widget.plPlayerController.isLive) {
        if (event is KeyDownEvent) {
          if (hasPlayer && !widget.plPlayerController.longPressStatus.value) {
            widget.plPlayerController
              ..longPressTimer?.cancel()
              ..longPressTimer = Timer(
                const Duration(milliseconds: 200),
                () => widget.plPlayerController
                  ..cancelLongPressTimer()
                  ..setLongPressStatus(true),
              );
          }
        } else if (event is KeyUpEvent) {
          widget.plPlayerController.cancelLongPressTimer();
          if (hasPlayer) {
            if (widget.plPlayerController.longPressStatus.value) {
              widget.plPlayerController.setLongPressStatus(false);
            } else {
              widget.plPlayerController.onForward(
                widget.plPlayerController.fastForBackwardDuration,
              );
            }
          }
        }
      }
      return true;
    }

    if (event is KeyDownEvent) {
      final isDigit1 = key == LogicalKeyboardKey.digit1;
      if (isDigit1 || key == LogicalKeyboardKey.digit2) {
        if (HardwareKeyboard.instance.isShiftPressed && hasPlayer) {
          final speed = isDigit1 ? 1.0 : 2.0;
          if (speed != widget.plPlayerController.playbackSpeed) {
            widget.plPlayerController.setPlaybackSpeed(speed);
          }
          SmartDialog.showToast('${speed}x播放');
        }
        return true;
      }

      switch (key) {
        case LogicalKeyboardKey.space:
          if (widget.plPlayerController.isLive || widget.canPlay!()) {
            if (hasPlayer) {
              widget.plPlayerController.onDoubleTapCenter();
            }
          }
          return true;

        case LogicalKeyboardKey.keyF:
          final isFullScreen = this.isFullScreen;
          if (isFullScreen && widget.plPlayerController.controlsLock.value) {
            widget.plPlayerController
              ..controlsLock.value = false
              ..showControls.value = false;
          }
          widget.plPlayerController.triggerFullScreen(
            status: !isFullScreen,
            inAppFullScreen: HardwareKeyboard.instance.isShiftPressed,
          );
          return true;

        case LogicalKeyboardKey.keyD:
          final newVal = !widget.plPlayerController.enableShowDanmaku.value;
          widget.plPlayerController.enableShowDanmaku.value = newVal;
          if (!widget.plPlayerController.tempPlayerConf) {
            GStorage.setting.put(
              widget.plPlayerController.isLive
                  ? SettingBoxKey.enableShowLiveDanmaku
                  : SettingBoxKey.enableShowDanmaku,
              newVal,
            );
          }
          return true;

        case LogicalKeyboardKey.keyP:
          if (PlatformUtils.isDesktop && hasPlayer && !isFullScreen) {
            widget.plPlayerController
              ..toggleDesktopPip()
              ..controlsLock.value = false
              ..showControls.value = false;
          }
          return true;

        case LogicalKeyboardKey.keyM:
          if (hasPlayer) {
            final isMuted = !widget.plPlayerController.isMuted;
            widget.plPlayerController.videoPlayerController!.setVolume(
              isMuted ? 0 : widget.plPlayerController.volume.value * 100,
            );
            widget.plPlayerController.isMuted = isMuted;
            SmartDialog.showToast('${isMuted ? '' : '取消'}静音');
          }
          return true;

        case LogicalKeyboardKey.keyS:
          if (hasPlayer && isFullScreen) {
            widget.plPlayerController.takeScreenshot();
          }
          return true;

        case LogicalKeyboardKey.keyL:
          if (isFullScreen || widget.plPlayerController.isDesktopPip) {
            widget.plPlayerController.onLockControl(
              !widget.plPlayerController.controlsLock.value,
            );
          }
          return true;

        case LogicalKeyboardKey.enter:
          // 桌面端Enter键保持原有逻辑（发送弹幕/跳过片头）
          if (widget.onSkipSegment?.call() ?? false) {
            return true;
          }
          widget.onSendDanmaku();
          return true;
      }

      if (!widget.plPlayerController.isLive) {
        switch (key) {
          case LogicalKeyboardKey.arrowLeft:
            if (hasPlayer) {
              widget.plPlayerController.onBackward(
                widget.plPlayerController.fastForBackwardDuration,
              );
            }
            return true;

          case LogicalKeyboardKey.keyW:
            if (HardwareKeyboard.instance.isMetaPressed) {
              return true;
            }
            widget.introController?.actionCoinVideo();
            return true;

          case LogicalKeyboardKey.keyE:
            widget.introController?.actionFavVideo(isQuick: true);
            return true;

          case LogicalKeyboardKey.keyT || LogicalKeyboardKey.keyV:
            widget.introController?.viewLater();
            return true;

          case LogicalKeyboardKey.keyG:
            if (widget.introController case final UgcIntroController ugcCtr) {
              ugcCtr.actionRelationMod(Get.context!);
            }
            return true;

          case LogicalKeyboardKey.bracketLeft:
            if (widget.introController case final introController?) {
              if (!introController.prevPlay()) {
                SmartDialog.showToast('已经是第一集了');
              }
            }
            return true;

          case LogicalKeyboardKey.bracketRight:
            if (widget.introController case final introController?) {
              if (!introController.nextPlay()) {
                SmartDialog.showToast('已经是最后一集了');
              }
            }
            return true;
        }
      }
    }

    return false;
  }
}
