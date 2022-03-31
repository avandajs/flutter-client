import 'package:avanda/avanda.dart';
import 'package:avanda/exceptions/request_exception.dart';
void main() async {
  // Avanda.setGraphRoot();
  Avanda.setHeaders({
    'Authorization': 'Bearer blabla'
  });
  Avanda.setConfig(AvandaConfig(rootUrl: "http://192.168.18.5:4000/"));

  // try{
    var res = await Avanda().service("User/watcherTest").data({'name': 'wale'}).watch((event) {
      print(event);
    });


    // res!.listen((event) {
    //   print(event.isError());
    // });

    //
    // Future.delayed(const Duration(seconds: 10),(){
    //   res.send({
    //     'name': 'wale'
    //   });
    // });


    //
    // Future.delayed(const Duration(seconds: 20),(){
    //   res.close();
    //   print('CLosing...');
    // });

    // print(res.rawResponse.status);
    // print(res.rawResponse.data);
    // print(res.getTotalPages());
  // }on RequestException catch(e){
  //   print(e.getResponse().msg);
  // }

}