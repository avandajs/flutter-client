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

  Map toJson() => {
    'n': n,
    'f': f,
    'c': c.map((e){
      if(e is Service){
        return e.toJson();
      }else{
        return e;
      }
    }).toList(),
    'a': a,
    'al': al,
    'p': p,
    'pr': pr,
    'ft': ft,
    'q': q?.toJson() ?? {}
  };

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
