mixin AStringMixin {
  String mix(String msg) {
    return String.fromCharCodes(msg.runes.toList()..shuffle());
  }
}

extension MixStringExt on String {
  String mix() {
    return String.fromCharCodes(runes.toList()..shuffle());
  }
}

void switchCase(num number) {
  switch (number) {
    case double():
      print('double');
    case int():
      print('int');
  }
}

bool check(String msg) {
  return msg.isEmpty ? true : false;
}

bool ifElseBrackets(String msg) {
  if (msg.isEmpty) {
    return true;
  } else {
    return false;
  }
}

bool ifElseFlat(String msg) {
  if (msg.isEmpty)
    // ignore: curly_braces_in_flow_control_structures
    return true;
  else
    // ignore: curly_braces_in_flow_control_structures
    return false;
}

// The VM emits only one branch entry (the if), no false-arm entry.
// The false path is only statement => a constant-literal return. The VM omits line data.
bool ifElseFallback(String msg) {
  if (msg.isEmpty) {
    return true;
  }

  return false;
}

// Expression-bodied (arrow) function: the body shares the declaration line, so
// the VM records it directly.
int square(int x) => x * x;

// else-if chain with an explicit final else and non-constant arms, so every
// branch is tracked by the VM.
String classify(int n) {
  if (n < 0) {
    return 'negative ($n)';
  } else if (n == 0) {
    return 'zero ($n)';
  } else {
    return 'positive ($n)';
  }
}

// `if`/`else` used as a collection element (an IfElement, not a statement).
List<String> labels(bool extra) {
  return [
    'base',
    if (extra) 'extra' else 'none',
  ];
}

// for loop accumulating a result.
int sumTo(int n) {
  var total = 0;
  for (var i = 1; i <= n; i++) {
    total += i;
  }
  return total;
}

// Class with a constructor, a getter and a method.
class Counter {
  int _value;

  Counter(this._value);

  int get value => _value;

  void increment() {
    _value++;
  }
}
