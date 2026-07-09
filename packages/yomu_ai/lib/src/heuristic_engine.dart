import 'dart:math';

import 'models.dart';

/// Offline-first intent engine (PT-BR). No network required.
///
/// Mutating intents become [ActionProposal]s — never auto-executed.
class HeuristicMayaEngine {
  HeuristicMayaEngine({Random? random}) : _rng = random ?? Random();

  final Random _rng;

  MayaTurn handle({
    required String userText,
    required List<MayaLibraryItem> library,
  }) {
    final text = userText.trim();
    final lower = _normalize(text);

    if (text.isEmpty) {
      return _reply('Diz o que precisa — biblioteca, continuar lendo, ajuda…');
    }

    if (_matches(lower, const [
      'ajuda',
      'help',
      'o que voce faz',
      'o que você faz',
      'comandos',
    ])) {
      return _reply(
        'Sou a Maya (modo local). Posso:\n'
        '• listar sua biblioteca\n'
        '• sugerir o que continuar\n'
        '• buscar um título na biblioteca\n'
        '• propor download / adicionar à biblioteca (você confirma)\n\n'
        'Exemplos: “biblioteca”, “continuar”, “busca dandadan”, “baixar capítulo”.',
      );
    }

    if (_matches(lower, const [
      'biblioteca',
      'library',
      'o que tenho',
      'minhas obras',
      'lista',
      'listar',
    ])) {
      return _libraryList(library);
    }

    if (_matches(lower, const [
      'continuar',
      'retomar',
      'continuar lendo',
      'proximo',
      'próximo',
      'em progresso',
      'lendo',
    ])) {
      return _continueReading(library);
    }

    final searchQ = _extractAfter(lower, const [
      'busca ',
      'buscar ',
      'procura ',
      'procurar ',
      'find ',
      'search ',
    ]);
    if (searchQ != null && searchQ.isNotEmpty) {
      return _search(library, searchQ);
    }

    // Free-text title match if library has a clear hit.
    final hits = _searchHits(library, lower);
    if (hits.length == 1 && lower.split(RegExp(r'\s+')).length <= 4) {
      final m = hits.first;
      final proposal = _proposal(
        kind: MayaActionKind.openManga,
        title: 'Abrir ${m.title}',
        description: 'Abrir a obra na biblioteca (mangaId ${m.id}).',
        payload: {'mangaId': m.id, 'title': m.title},
      );
      return MayaTurn(
        assistantMessage: _msg(
          'Encontrei **${m.title}**'
          '${m.unreadCount > 0 ? ' (${m.unreadCount} não lidos)' : ''}. '
          'Confirme para abrir.',
          proposalIds: [proposal.id],
        ),
        proposals: [proposal],
      );
    }

    if (_matches(lower, const ['baixar', 'download', 'offline'])) {
      final cont = _continueItems(library);
      if (cont.isEmpty) {
        return _reply(
          'Não achei capítulo recente para baixar. '
          'Abra uma obra no desktop e leia um pouco, ou diga “biblioteca”.',
        );
      }
      final m = cont.first;
      if (m.lastChapterId == null) {
        return _reply(
          '**${m.title}** não tem capítulo de retomada conhecido. '
          'Abra a obra no desktop para carregar capítulos.',
        );
      }
      final proposal = _proposal(
        kind: MayaActionKind.downloadChapter,
        title: 'Baixar capítulo de ${m.title}',
        description:
            'Enfileirar download do capítulo ${m.lastChapterName ?? m.lastChapterId} '
            '(id ${m.lastChapterId}).',
        payload: {
          'mangaId': m.id,
          'chapterId': m.lastChapterId,
          'title': m.title,
        },
      );
      return MayaTurn(
        assistantMessage: _msg(
          'Posso enfileirar o download do último capítulo de **${m.title}**. '
          'Isso só roda se você confirmar.',
          proposalIds: [proposal.id],
        ),
        proposals: [proposal],
      );
    }

    if (library.isEmpty) {
      return _reply(
        'Sua biblioteca está vazia. No desktop: Explorar → adicionar obras. '
        'Depois diga “biblioteca” ou “continuar”.',
      );
    }

    return _reply(
      'Não entendi com certeza. Tente “biblioteca”, “continuar”, '
      '“busca <título>” ou “ajuda”. '
      'Você tem ${library.length} obra(s) na biblioteca.',
    );
  }

  MayaTurn _libraryList(List<MayaLibraryItem> library) {
    if (library.isEmpty) {
      return _reply('Biblioteca vazia. Adicione obras em Explorar no desktop.');
    }
    final buf = StringBuffer('Biblioteca (${library.length}):\n');
    for (final m in library.take(25)) {
      buf.writeln(
        '• ${m.title}'
        '${m.unreadCount > 0 ? ' — ${m.unreadCount} não lidos' : ''}'
        '${m.lastChapterName != null ? ' — último: ${m.lastChapterName}' : ''}',
      );
    }
    if (library.length > 25) {
      buf.writeln('… e mais ${library.length - 25}.');
    }
    return _reply(buf.toString().trimRight());
  }

  MayaTurn _continueReading(List<MayaLibraryItem> library) {
    final cont = _continueItems(library);
    if (cont.isEmpty) {
      return _reply(
        'Nada em progresso óbvio. Tente “biblioteca” ou abra uma obra e leia um capítulo.',
      );
    }
    final proposals = <ActionProposal>[];
    final buf = StringBuffer('Para continuar:\n');
    for (final m in cont.take(5)) {
      final p = _proposal(
        kind: MayaActionKind.openManga,
        title: 'Abrir ${m.title}',
        description: m.lastChapterName != null
            ? 'Retomar em ${m.lastChapterName}'
            : 'Abrir ${m.title}',
        payload: {
          'mangaId': m.id,
          'title': m.title,
          if (m.lastChapterId != null) 'chapterId': m.lastChapterId,
        },
      );
      proposals.add(p);
      buf.writeln(
        '• **${m.title}**'
        '${m.unreadCount > 0 ? ' (${m.unreadCount} não lidos)' : ''}'
        '${m.lastChapterName != null ? ' — ${m.lastChapterName}' : ''}',
      );
    }
    buf.writeln('\nConfirme um cartão abaixo para abrir no app.');
    return MayaTurn(
      assistantMessage: _msg(
        buf.toString().trimRight(),
        proposalIds: proposals.map((p) => p.id).toList(),
      ),
      proposals: proposals,
    );
  }

  MayaTurn _search(List<MayaLibraryItem> library, String q) {
    final hits = _searchHits(library, q);
    if (hits.isEmpty) {
      return _reply('Nada na biblioteca com “$q”.');
    }
    final proposals = <ActionProposal>[];
    final buf = StringBuffer('Encontrei ${hits.length}:\n');
    for (final m in hits.take(8)) {
      final p = _proposal(
        kind: MayaActionKind.openManga,
        title: 'Abrir ${m.title}',
        description: 'Abrir ${m.title} (id ${m.id})',
        payload: {'mangaId': m.id, 'title': m.title},
      );
      proposals.add(p);
      buf.writeln('• ${m.title}');
    }
    return MayaTurn(
      assistantMessage: _msg(
        buf.toString().trimRight(),
        proposalIds: proposals.map((e) => e.id).toList(),
      ),
      proposals: proposals,
    );
  }

  List<MayaLibraryItem> _continueItems(List<MayaLibraryItem> library) {
    final withUnread = library.where((m) => m.unreadCount > 0).toList()
      ..sort((a, b) => b.unreadCount.compareTo(a.unreadCount));
    if (withUnread.isNotEmpty) return withUnread;
    return library.where((m) => m.lastChapterId != null).toList();
  }

  List<MayaLibraryItem> _searchHits(List<MayaLibraryItem> library, String q) {
    final needle = _normalize(q);
    if (needle.isEmpty) return const [];
    return library
        .where((m) => _normalize(m.title).contains(needle))
        .toList();
  }

  String _normalize(String s) {
    var t = s.toLowerCase().trim();
    const map = {
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'é': 'e',
      'ê': 'e',
      'í': 'i',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ú': 'u',
      'ç': 'c',
    };
    map.forEach((k, v) => t = t.replaceAll(k, v));
    return t;
  }

  bool _matches(String lower, List<String> keys) {
    for (final k in keys) {
      if (lower == k || lower.contains(k)) return true;
    }
    return false;
  }

  String? _extractAfter(String lower, List<String> prefixes) {
    for (final p in prefixes) {
      final i = lower.indexOf(p);
      if (i >= 0) {
        return lower.substring(i + p.length).trim();
      }
    }
    return null;
  }

  ActionProposal _proposal({
    required MayaActionKind kind,
    required String title,
    required String description,
    required Map<String, dynamic> payload,
  }) {
    return ActionProposal(
      id: _id('p'),
      kind: kind,
      title: title,
      description: description,
      payload: payload,
      status: ActionProposalStatus.pending,
      createdAt: DateTime.now(),
    );
  }

  MayaTurn _reply(String text) =>
      MayaTurn(assistantMessage: _msg(text), proposals: const []);

  MayaMessage _msg(String text, {List<String> proposalIds = const []}) {
    return MayaMessage(
      id: _id('m'),
      role: MayaRole.assistant,
      text: text,
      createdAt: DateTime.now(),
      proposalIds: proposalIds,
    );
  }

  String _id(String prefix) {
    final n = _rng.nextInt(1 << 32).toRadixString(16);
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}-$n';
  }
}
