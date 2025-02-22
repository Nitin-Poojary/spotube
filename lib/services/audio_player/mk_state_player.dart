import 'dart:async';

import 'package:collection/collection.dart';
import 'package:media_kit/media_kit.dart';
// ignore: implementation_imports
import 'package:media_kit/src/models/playable.dart';
import 'package:spotube/services/audio_player/playback_state.dart';

/// MediaKit [Player] by default doesn't have a state stream.
/// This class adds a state stream to the [Player] class.
class MkPlayerWithState extends Player {
  final StreamController<AudioPlaybackState> _playerStateStream;
  final StreamController<Playlist> _playlistStream;
  final StreamController<bool> _shuffleStream;
  final StreamController<PlaylistMode> _loopModeStream;

  late final List<StreamSubscription> _subscriptions;

  bool _shuffled;
  PlaylistMode _loopMode;

  Playlist? _playlist;
  List<Media>? _tempMedias;

  MkPlayerWithState({super.configuration})
      : _playerStateStream = StreamController.broadcast(),
        _shuffleStream = StreamController.broadcast(),
        _loopModeStream = StreamController.broadcast(),
        _playlistStream = StreamController.broadcast(),
        _shuffled = false,
        _loopMode = PlaylistMode.none {
    _subscriptions = [
      streams.buffering.listen((event) {
        _playerStateStream.add(AudioPlaybackState.buffering);
      }),
      streams.playing.listen((playing) {
        if (playing) {
          _playerStateStream.add(AudioPlaybackState.playing);
        } else {
          _playerStateStream.add(AudioPlaybackState.paused);
        }
      }),
      streams.position.listen((position) async {
        final isComplete = state.duration != Duration.zero &&
            position != Duration.zero &&
            state.duration.inSeconds == position.inSeconds;

        if (!isComplete || _playlist == null) return;
        _playerStateStream.add(AudioPlaybackState.completed);

        if (loopMode == PlaylistMode.single) {
          await super.open(_playlist!.medias[_playlist!.index], play: true);
        } else {
          await next();
          await Future.delayed(const Duration(milliseconds: 250), play);
        }
      }),
      streams.playlist.listen((event) {
        if (event.medias.isEmpty) {
          _playerStateStream.add(AudioPlaybackState.stopped);
        }
      }),
    ];
  }

  bool get shuffled => _shuffled;
  PlaylistMode get loopMode => _loopMode;
  Playlist get playlist => _playlist ?? const Playlist([], index: -1);

  Stream<AudioPlaybackState> get playerStateStream => _playerStateStream.stream;
  Stream<bool> get shuffleStream => _shuffleStream.stream;
  Stream<PlaylistMode> get loopModeStream => _loopModeStream.stream;
  Stream<Playlist> get playlistStream => _playlistStream.stream;
  Stream<int> get indexChangeStream {
    int oldIndex = playlist.index;
    return playlistStream.map((event) => event.index).where((newIndex) {
      if (newIndex != oldIndex) {
        oldIndex = newIndex;
        return true;
      }
      return false;
    });
  }

  set playlist(Playlist playlist) {
    _playlist = playlist;
    _playlistStream.add(playlist);
  }

  @override
  Future<void> setShuffle(bool shuffle) async {
    _shuffled = shuffle;
    if (shuffle) {
      _tempMedias = _playlist!.medias;
      final active = _playlist!.medias[_playlist!.index];
      final newMedias = _playlist!.medias.toList()..shuffle();
      playlist = _playlist!.copyWith(
        medias: newMedias,
        index: newMedias.indexOf(active),
      );
    } else {
      if (_tempMedias == null) return;
      playlist = _playlist!.copyWith(
        medias: _tempMedias!,
        index: _tempMedias?.indexOf(
          _playlist!.medias[_playlist!.index],
        ),
      );
      _tempMedias = null;
    }
    await super.setShuffle(shuffle);
    _shuffleStream.add(shuffle);
  }

  @override
  Future<void> setPlaylistMode(PlaylistMode playlistMode) async {
    _loopMode = playlistMode;
    await super.setPlaylistMode(playlistMode);
    _loopModeStream.add(playlistMode);
  }

  Future<void> stop() async {
    await pause();
    await seek(Duration.zero);

    _loopMode = PlaylistMode.none;
    _shuffled = false;
    _playlist = null;
    _tempMedias = null;
    _playerStateStream.add(AudioPlaybackState.stopped);
    _shuffleStream.add(false);
  }

  @override
  FutureOr<void> dispose({int code = 0}) {
    for (var element in _subscriptions) {
      element.cancel();
    }
    return super.dispose(code: code);
  }

  @override
  Future<void> open(
    Playable playable, {
    bool play = true,
  }) async {
    await stop();
    if (playable is Playlist) {
      playlist = playable;
      super.open(playable.medias[playable.index], play: play);
    }
    await super.open(playable, play: play);
  }

  @override
  FutureOr<void> next() {
    if (_playlist == null || _playlist!.index + 1 >= _playlist!.medias.length) {
      return null;
    }

    final isLast = _playlist!.index == _playlist!.medias.length - 1;

    if (loopMode == PlaylistMode.loop && isLast) {
      playlist = _playlist!.copyWith(index: 0);
      return super.open(_playlist!.medias[_playlist!.index], play: true);
    } else if (!isLast) {
      playlist = _playlist!.copyWith(index: _playlist!.index + 1);
      return super.open(_playlist!.medias[_playlist!.index], play: true);
    }
  }

  @override
  FutureOr<void> previous() {
    if (_playlist == null || _playlist!.index - 1 < 0) return null;

    if (loopMode == PlaylistMode.loop && _playlist!.index == 0) {
      playlist = _playlist!.copyWith(index: _playlist!.medias.length - 1);
      return super.open(_playlist!.medias[_playlist!.index], play: true);
    } else if (_playlist!.index != 0) {
      playlist = _playlist!.copyWith(index: _playlist!.index - 1);
      return super.open(_playlist!.medias[_playlist!.index], play: true);
    }
  }

  @override
  FutureOr<void> jump(int index) {
    if (_playlist == null || index < 0 || index >= _playlist!.medias.length) {
      return null;
    }

    playlist = _playlist!.copyWith(index: index);
    return super.open(_playlist!.medias[index], play: true);
  }

  @override
  FutureOr<void> move(int from, int to) {
    if (_playlist == null ||
        from >= _playlist!.medias.length ||
        to >= _playlist!.medias.length) return null;

    final active = _playlist!.medias[_playlist!.index];
    final newPlaylist = _playlist!.copyWith(
      medias: _playlist!.medias.mapIndexed((index, element) {
        if (index == from) {
          return _playlist!.medias[to];
        } else if (index == to) {
          return _playlist!.medias[from];
        }
        return element;
      }).toList(),
    );
    playlist = _playlist!.copyWith(
      index: newPlaylist.medias.indexOf(active),
      medias: newPlaylist.medias,
    );
  }

  /// This replaces the old source with a new one
  ///
  /// If the old source is playing, the new one will play
  /// from the beginning
  ///
  /// This doesn't work when [playlist] is null
  void replace(String oldUrl, String newUrl) {
    if (_playlist == null) {
      return;
    }

    final isOldUrlPlaying = _playlist!.medias[_playlist!.index].uri == oldUrl;

    for (var i = 0; i < _playlist!.medias.length - 1; i++) {
      final media = _playlist!.medias[i];
      if (media.uri == oldUrl) {
        if (isOldUrlPlaying) {
          pause();
        }
        final newMedias = _playlist!.medias.toList();
        newMedias[i] = Media(newUrl, extras: media.extras);
        playlist = _playlist!.copyWith(medias: newMedias);
        if (isOldUrlPlaying) {
          super.open(
            newMedias[i],
            play: true,
          );
        }

        // replace in the _tempMedias if it's not null
        if (shuffled && _tempMedias != null) {
          final tempIndex = _tempMedias!.indexOf(media);
          _tempMedias![tempIndex] = Media(newUrl, extras: media.extras);
        }
        break;
      }
    }
  }

  @override
  FutureOr<void> add(Media media) {
    if (_playlist == null) return null;

    playlist = _playlist!.copyWith(
      medias: [..._playlist!.medias, media],
    );

    if (shuffled && _tempMedias != null) {
      _tempMedias!.add(media);
    }
  }

  FutureOr<void> insert(int index, Media media) {
    if (_playlist == null ||
        index < 0 ||
        (_playlist!.medias.length > 1 &&
            index > _playlist!.medias.length - 1)) {
      return null;
    }

    final newMedias = _playlist!.medias.toList()..insert(index, media);

    playlist = _playlist!.copyWith(
      medias: newMedias,
      index: newMedias.indexOf(_playlist!.medias[_playlist!.index]),
    );

    if (shuffled && _tempMedias != null) {
      _tempMedias!.insert(index, media);
    }
  }

  /// Doesn't work when active media is the one to be removed
  @override
  FutureOr<void> remove(int index) async {
    if (_playlist == null ||
        index < 0 ||
        index > _playlist!.medias.length - 1 ||
        _playlist!.index == index) {
      return null;
    }

    final targetItem = _playlist!.medias.elementAtOrNull(index);
    if (targetItem == null) return null;

    if (shuffled && _tempMedias != null) {
      _tempMedias!.remove(targetItem);
    }

    final newMedias = _playlist!.medias.toList()..removeAt(index);

    playlist = _playlist!.copyWith(
      medias: newMedias,
      index: newMedias.indexOf(_playlist!.medias[_playlist!.index]),
    );
  }
}
