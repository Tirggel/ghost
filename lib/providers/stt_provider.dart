import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive_io.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class SttState {

  SttState({
    required this.isReady,
    required this.isDownloading,
    required this.downloadProgress,
    required this.isRecording,
    required this.isTranscribing,
  });

  factory SttState.initial() => SttState(
        isReady: false,
        isDownloading: false,
        downloadProgress: 0.0,
        isRecording: false,
        isTranscribing: false,
      );
  final bool isReady;
  final bool isDownloading;
  final double downloadProgress;
  final bool isRecording;
  final bool isTranscribing;

  SttState copyWith({
    bool? isReady,
    bool? isDownloading,
    double? downloadProgress,
    bool? isRecording,
    bool? isTranscribing,
  }) {
    return SttState(
      isReady: isReady ?? this.isReady,
      isDownloading: isDownloading ?? this.isDownloading,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      isRecording: isRecording ?? this.isRecording,
      isTranscribing: isTranscribing ?? this.isTranscribing,
    );
  }
}

final sttProvider = NotifierProvider<SttNotifier, SttState>(() {
  return SttNotifier();
});

class SttNotifier extends Notifier<SttState> {
  static const modelUrl = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2';
  static const modelDirName = 'sherpa-onnx-whisper-base';

  sherpa.OfflineRecognizer? _recognizer;
  final _audioRecorder = AudioRecorder();
  String? _recordingPath;

  @override
  SttState build() {
    ref.onDispose(() {
      _audioRecorder.dispose();
    });
    _init();
    return SttState.initial();
  }

  Future<void> _init() async {
    final docsDir = await getApplicationSupportDirectory();
    final modelDir = Directory('${docsDir.path}/$modelDirName');

    if (await modelDir.exists()) {
      await _initRecognizer(modelDir.path);
    }
  }

  Future<void> ensureModelReady() async {
    if (state.isReady) return;
    
    final docsDir = await getApplicationSupportDirectory();
    final modelDir = Directory('${docsDir.path}/$modelDirName');

    if (await modelDir.exists()) {
      await _initRecognizer(modelDir.path);
      return;
    }

    state = state.copyWith(isDownloading: true, downloadProgress: 0.0);

    try {
      final archiveFile = File('${docsDir.path}/whisper-base.tar.bz2');
      
      final request = http.Request('GET', Uri.parse(modelUrl));
      final response = await http.Client().send(request);
      final totalBytes = response.contentLength ?? 1;
      
      int downloadedBytes = 0;
      final sink = archiveFile.openWrite();
      
      await response.stream.forEach((chunk) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        state = state.copyWith(downloadProgress: downloadedBytes / totalBytes);
      });
      await sink.close();

      state = state.copyWith(downloadProgress: 1.0);
      
      final bzip2Decoder = BZip2Decoder();
      final tarData = bzip2Decoder.decodeBytes(archiveFile.readAsBytesSync());
      final archive = TarDecoder().decodeBytes(tarData);
      
      for (final file in archive) {
        final filename = file.name;
        if (file.isFile) {
          final data = file.content as List<int>;
          final outFile = File('${docsDir.path}/$filename');
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(data);
        } else {
          await Directory('${docsDir.path}/$filename').create(recursive: true);
        }
      }
      
      await archiveFile.delete(); 
      await _initRecognizer(modelDir.path);
    } catch (e) {
      debugPrint('STT Model download/extract error: $e');
      state = state.copyWith(isDownloading: false);
    }
  }

  Future<void> _initRecognizer(String basePath) async {
    try {
      sherpa.initBindings();
    } catch (_) {
      // Ignored if already initialized
    }
    
    final config = sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        whisper: sherpa.OfflineWhisperModelConfig(
          encoder: '$basePath/base-encoder.onnx',
          decoder: '$basePath/base-decoder.onnx',
          language: 'de',
          task: 'transcribe',
        ),
        tokens: '$basePath/base-tokens.txt',
        numThreads: 2,
        debug: false,
      ),
    );

    try {
      _recognizer = sherpa.OfflineRecognizer(config);
      state = state.copyWith(isReady: true, isDownloading: false);
    } catch (e) {
      debugPrint('STT recognizer init error: $e');
      state = state.copyWith(isDownloading: false);
    }
  }

  Future<void> toggleRecording(void Function(String) onResult) async {
    if (state.isDownloading || state.isTranscribing) return;

    if (!state.isReady) {
      await ensureModelReady();
      if (!state.isReady) return; 
    }

    if (state.isRecording) {
      final path = await _audioRecorder.stop();
      state = state.copyWith(isRecording: false);
      
      if (path != null) {
        state = state.copyWith(isTranscribing: true);
        await Future<void>.delayed(const Duration(milliseconds: 50)); 
        
        try {
          final waveData = sherpa.readWave(path);
          final stream = _recognizer!.createStream();
          stream.acceptWaveform(sampleRate: waveData.sampleRate, samples: waveData.samples);
          _recognizer?.decode(stream);
          final result = _recognizer?.getResult(stream);
          if (result != null && result.text.isNotEmpty) {
             onResult(result.text);
          }
        } catch (e) {
          debugPrint('Transcription error: $e');
        } finally {
          state = state.copyWith(isTranscribing: false);
          try { File(path).deleteSync(); } catch (_) {}
        }
      }
    } else {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        _recordingPath = '${tempDir.path}/stt_temp_${DateTime.now().millisecondsSinceEpoch}.wav';
        
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.wav,
            sampleRate: 16000,
            numChannels: 1,
            bitRate: 256000, 
          ),
          path: _recordingPath!,
        );
        state = state.copyWith(isRecording: true);
      }
    }
  }
}
