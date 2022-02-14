import 'package:avanda/exceptions/request_exception.dart';
import 'package:avanda/types/ResponseStruct.dart';

class AccessForbiddenError extends RequestException{
  AccessForbiddenError(ResponseStruct response) : super(response);
}