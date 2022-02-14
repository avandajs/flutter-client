import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/types/ResponseStruct.dart';

class UnknownError extends RequestException{
  UnknownError(ResponseStruct response) : super(response);
}