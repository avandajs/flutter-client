import 'package:avanda/types/ResponseStruct.dart';

abstract class RequestException implements Exception{
  ResponseStruct response;
  RequestException(this.response);

  ResponseStruct getResponse(){
    return response;
  }
}