import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/types/ResponseStruct.dart';

class MethodNotAllowedError extends RequestException{
  MethodNotAllowedError(ResponseStruct response) : super(response);
}