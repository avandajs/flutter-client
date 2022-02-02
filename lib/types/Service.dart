import 'dart:ffi';

import 'package:avanda/types/Query.dart';

class Service {
  String? n; /// service name
  String? f; /// service function
  List c; /// service columns
  String? a; /// service alias
  bool? al; /// should auto-link
  int p; /// service page
  Map pr; /// Service params
  Map ft;
  Query? q;
  Service({
    this.a,
    this.q,
    this.al,
    this.n,
    this.f,
    required this.ft,
    required this.c,
    required this.p,
    required this.pr,/// Service params
  });
}
