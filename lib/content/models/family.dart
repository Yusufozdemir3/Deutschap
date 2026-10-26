import '../json_utils.dart';

/// Words that share a root (fahren, die Fahrt, der Fahrer …), learnt
/// together because one explains the others.
class WordFamily {
  const WordFamily({required this.id, required this.root, required this.tr, required this.members, required this.noteTr});
  final String id;
  final String root;
  final String tr;
  final List<String> members;
  final String noteTr;

  factory WordFamily.fromJson(Json j) => WordFamily(
        id: j.str('id'),
        root: j.str('root'),
        tr: j.str('tr'),
        members: j.strList('members'),
        noteTr: j.str('note_tr'),
      );
}
