import 'package:avanda/avanda.dart';
void main() async {
  Avanda.setGraphRoot("https://graph.tyfarms.com/");

  print(await Avanda().service("User/login").post({}));
}