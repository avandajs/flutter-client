import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/types/ResponseStruct.dart';

class BadRequestError extends RequestException{
  BadRequestError(ResponseStruct response) : super(response);
}