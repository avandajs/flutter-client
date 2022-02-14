import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/types/ResponseStruct.dart';

class InternalServerError extends RequestException{
  InternalServerError(ResponseStruct response) : super(response);
}