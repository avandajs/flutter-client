import 'package:avanda/avanda.dart';

main() async {
  Avanda.setGraphRoot("https://graph.tyfarms.com/");

  var avanda = Avanda();

  print(await avanda.service('test/testFnc').get());
}
