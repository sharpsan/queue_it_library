import 'dart:math';

class ReadableUuid {
  factory ReadableUuid() => _instance;
  ReadableUuid._();
  static final ReadableUuid _instance = ReadableUuid._();

  final _random = Random();

  /// Generates a readable UUID using a combination of words and phrases.
  ///
  /// 0.11574074% chance of generating the same readable uuid
  ///
  /// ((6 + 6) * 6 * 6) * 2 = 864
  /// 1 / 864 = 0.0011574074
  String generateReadableUuid() {
    final animal = _animals[_random.nextInt(_animals.length)];
    final noun = _nouns[_random.nextInt(_nouns.length)];
    final verb = _verbs[_random.nextInt(_verbs.length)];
    final adjective = _adjectives[_random.nextInt(_adjectives.length)];

    String phrase;

    /// (adjective OR verb) noun animal
    if (_random.nextBool()) {
      phrase = '$adjective $noun $animal';
    } else {
      phrase = '$verb $noun $animal';
    }

    /// 50% chance to reverse the order
    if (_random.nextBool()) {
      phrase = phrase.split(' ').reversed.join(' ');
    }

    return phrase;
  }

  final _animals = ['cat', 'dog', 'bird', 'fish', 'rabbit', 'goose'];
  final _nouns = ['wizard', 'rock', 'carrot', 'donut', 'leaf', 'hat'];
  final _verbs = [
    'jumping',
    'running',
    'flying',
    'swimming',
    'hopping',
    'sleeping'
  ];
  final _adjectives = ['big', 'small', 'tall', 'short', 'round', 'flat'];
}
