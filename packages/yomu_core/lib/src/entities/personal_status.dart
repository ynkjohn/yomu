/// User intention status stored in Yomu SQLite (not Suwayomi facts).
enum PersonalStatus {
  wantToRead,
  reading,
  paused,
  completed,
  dropped;

  String get label => switch (this) {
        PersonalStatus.wantToRead => 'Quero ler',
        PersonalStatus.reading => 'Lendo',
        PersonalStatus.paused => 'Pausado',
        PersonalStatus.completed => 'Concluído',
        PersonalStatus.dropped => 'Dropado',
      };
}
