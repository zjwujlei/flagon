library flagon;

import 'dart:mirrors';

/// A Calculator.
class Calculator {
  /// Returns [value] plus 1.



  int add(){
    return a(1);
  }
}

typedef int addOne(int value);

addOne a = (int value)=>value+1;

