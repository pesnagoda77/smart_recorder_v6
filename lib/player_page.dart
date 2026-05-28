import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'audio_service.dart';

class PlayerPage extends StatefulWidget {
  final Recording recording;

  const PlayerPage({super.key, required this.recording});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final _player = AudioPlayer();
  bool _isPlaying = false;
  double _speed = 1.0;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    await _player.setFilePath(widget.recording.filePath);
    _duration = _player.duration ?? Duration.zero;

    _player.positionStream.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.playerStateStream.listen((state) {
      if (mounted) setState(() => _isPlaying = state.playing);
    });
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  void _setSpeed(double speed) {
    setState(() => _speed = speed);
    _player.setSpeed(speed);
  }

  Future<void> _seek(double value) async {
    final pos =
        Duration(milliseconds: (value * _duration.inMilliseconds).round());
    await _player.seek(pos);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? _position.inMilliseconds / _duration.inMilliseconds
        : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Прослушивание'),
        actions: [
          // Скорость
          PopupMenuButton<double>(
            initialValue: _speed,
            onSelected: _setSpeed,
            itemBuilder: (context) => [
              const PopupMenuItem(value: 0.5, child: Text('0.5x')),
              const PopupMenuItem(value: 1.0, child: Text('1.0x')),
              const PopupMenuItem(value: 1.25, child: Text('1.25x')),
              const PopupMenuItem(value: 1.5, child: Text('1.5x')),
              const PopupMenuItem(value: 2.0, child: Text('2.0x')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${_speed}x',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Название
            Text(
              'Запись ${widget.recording.createdAt.day}.${widget.recording.createdAt.month} ${widget.recording.createdAt.hour}:${widget.recording.createdAt.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${_fmtDuration(_position)} / ${_fmtDuration(_duration)}',
              style: const TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 48),

            // Ползунок
            Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: _seek,
              activeColor: Theme.of(context).colorScheme.primary,
              inactiveColor: Colors.white.withOpacity(0.1),
            ),

            const SizedBox(height: 48),

            // Кнопки управления
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Назад 10 сек
                IconButton(
                  icon: const Icon(Icons.replay_10, size: 36),
                  onPressed: () =>
                      _player.seek(_position - const Duration(seconds: 10)),
                ),
                const SizedBox(width: 32),

                // Play/Pause
                GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 32),

                // Вперёд 10 сек
                IconButton(
                  icon: const Icon(Icons.forward_10, size: 36),
                  onPressed: () =>
                      _player.seek(_position + const Duration(seconds: 10)),
                ),
              ],
            ),

            const SizedBox(height: 32),

            // Кнопки скорости быстрые
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _SpeedChip(
                  label: '1x',
                  isActive: _speed == 1.0,
                  onTap: () => _setSpeed(1.0),
                ),
                const SizedBox(width: 12),
                _SpeedChip(
                  label: '1.5x',
                  isActive: _speed == 1.5,
                  onTap: () => _setSpeed(1.5),
                ),
                const SizedBox(width: 12),
                _SpeedChip(
                  label: '2x',
                  isActive: _speed == 2.0,
                  onTap: () => _setSpeed(2.0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeedChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SpeedChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive
              ? Theme.of(context).colorScheme.primary
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isActive ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}
