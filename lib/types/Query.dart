class Query {
  String? c;
  String? k;

  Query({this.c,this.k});
  Map toJson() => {
    'c': c,
    'k': k
  };
}