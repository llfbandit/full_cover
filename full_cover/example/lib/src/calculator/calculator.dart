class Calculator {
  int add(int a, int b) => a + b;

  int subtract(int a, int b) => a - b;

  // Not covered by tests — shows partial line coverage
  int multiply(int a, int b) => a * b;

  // Not covered by tests — shows branch coverage gap
  double divide(int a, int b) {
    if (b == 0) throw ArgumentError('Cannot divide by zero');
    return a / b;
  }
}
