import 'dart:async';

class Debounce {
  late final Duration _duration;

  Debounce({Duration duration = const Duration(seconds: 1)}) : _duration = duration;

  Timer? _timer;

  void debounce(Function action) {
    _timer?.cancel();
    _timer = Timer(_duration, () => action());
  }
}