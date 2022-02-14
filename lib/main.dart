import 'package:avanda/avanda.dart';
import 'package:avanda/exceptions/request_exception.dart';
void main() async {
  Avanda.setGraphRoot("https://graph.tyfarms.com/");

  try{
    var res = await Avanda().service("User/login").post({});
    print(res.rawResponse.status);
    print(res.rawResponse.data);
  }on RequestException catch(e){
    print(e);
  }

}