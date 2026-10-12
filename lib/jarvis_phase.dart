enum JarvisPhase { ready, listening, thinking, speaking }

extension JarvisPhasePresentation on JarvisPhase {
  String get label => switch (this) {
    JarvisPhase.ready => 'SYSTEM READY',
    JarvisPhase.listening => 'LISTENING',
    JarvisPhase.thinking => 'PROCESSING',
    JarvisPhase.speaking => 'RESPONDING',
  };

  String get orbLabel => switch (this) {
    JarvisPhase.ready => 'AWAITING\nCOMMAND',
    JarvisPhase.listening => 'I’M\\nLISTENING',
    JarvisPhase.thinking => 'THINKING',
    JarvisPhase.speaking => 'SPEAKING',
  };
}
